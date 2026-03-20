const express = require('express');
const cors = require('cors');
const { MongoClient, ObjectId } = require('mongodb');
const axios = require('axios');
const FormData = require('form-data');
require('dotenv').config();

const app = express();
const port = process.env.PORT || 3000;

app.use(cors());
app.use(express.json({ limit: '100mb' }));
app.use(express.urlencoded({ limit: '100mb', extended: true }));

const uri = process.env.MONGODB_URI;
const client = new MongoClient(uri);

let db;

async function connectDB() {
  try {
    await client.connect();
    db = client.db(process.env.DB_NAME || 'magr_db');
    console.log("Connected to MongoDB Atlas");
  } catch (e) {
    console.error("Connection failed", e);
  }
}

connectDB();

// Helper to clean and format IDs for Flutter
function cleanDoc(doc) {
  if (doc && doc._id) {
    doc._id = doc._id.toString();
  }
  return doc;
}

// --- NEW: Global Grading Queue ---
let gradingQueue = [];
let isProcessingQueue = false;

async function addToGradingQueue(batchId, submissionIds, webhookUrl, commonMetadata) {
  // Thêm tất cả bài làm của Batch vào hàng đợi chung
  for (const subId of submissionIds) {
    gradingQueue.push({
      batchId,
      subId,
      webhookUrl,
      commonMetadata
    });
  }

  console.log(`\x1b[35m[Queue]\x1b[0m Đã thêm ${submissionIds.length} bài vào hàng đợi. Tổng cộng: ${gradingQueue.length} bài.`);

  if (!isProcessingQueue) {
    processGlobalQueue();
  }
}

async function processGlobalQueue() {
  if (gradingQueue.length === 0) {
    isProcessingQueue = false;
    console.log(`\x1b[35m[Queue]\x1b[0m Hàng đợi đã trống.`);
    return;
  }

  isProcessingQueue = true;
  const task = gradingQueue.shift();
  const { batchId, subId, webhookUrl, commonMetadata } = task;

  const subCol = db.collection('submissions');
  const sessionCol = db.collection('gradings');
  const batchCol = db.collection('grading_batches');

  let isSuccess = false;
  let studentDisplayName = "Ẩn danh";
  let batchSheetUrl = commonMetadata?.googleSheetId ? `https://docs.google.com/spreadsheets/d/${commonMetadata.googleSheetId}` : null;

  try {
    const sub = await subCol.findOne({ _id: new ObjectId(subId) });
    if (!sub) {
      console.error(`  [!] Không tìm thấy bài nộp ID: ${subId}`);
    } else {
      studentDisplayName = sub.studentName;
      console.log(`\x1b[33m[Processing]\x1b[0m [Batch ${batchId}] Đang chấm: ${studentDisplayName}... (${gradingQueue.length} bài còn lại)`);

      const form = new FormData();
      const sessionMetadata = { ...commonMetadata, studentName: sub.studentName, batchId: batchId.toString() };

      form.append('data', Buffer.from(JSON.stringify(sessionMetadata)), {
        filename: 'data.json',
        contentType: 'application/json'
      });

      let base64Str = sub.imageBase64 || "";
      if (base64Str.includes(',')) base64Str = base64Str.split(',')[1];
      const imageBuffer = Buffer.from(base64Str, 'base64');

      form.append('studentImage', imageBuffer, {
        filename: `${sub.studentName}.jpg`,
        contentType: 'image/jpeg'
      });

      // N8n dùng Respond Immediately nên thời gian chốt yêu cầu cực nhanh
      const response = await axios.post(webhookUrl, form, {
        headers: form.getHeaders(),
        timeout: 20000 // Chỉ cho tối đa 20s để n8n xác nhận đã nhận đơn
      });

      // 1. Phát tín hiệu cho App Flutter hiện chữ "Đang chấm..." và xoay xoay đẹp mắt
      await sessionCol.updateOne(
        { batchId: batchId.toString(), studentName: sub.studentName },
        { $set: { n8nStatus: 'Processing', errorDetails: null } }
      );

      // 2. Node.js chuyển sang chế độ "Đứng Canh Cửa" (Polling DB)
      // Chờ cục MongoDB Node trên n8n đâm lén kết quả vào sau 125s
      let waitSeconds = 0;
      const maxWaitSeconds = 300; // Phóng khoáng cho đợi tối đa 5 phút
      let finalSession = null;

      while (waitSeconds < maxWaitSeconds) {
        await new Promise(resolve => setTimeout(resolve, 4000)); // 4 giây ngó nhà 1 lần
        waitSeconds += 4;

        finalSession = await sessionCol.findOne({ batchId: batchId.toString(), studentName: studentDisplayName });
        
        if (finalSession && finalSession.n8nStatus === 'Success') {
           isSuccess = true;
           // Nếu n8n có ghi sheetUrl thì kéo ra lưu vào batch để lúc nào xem
           if (finalSession.sheetUrl) batchSheetUrl = finalSession.sheetUrl;
           break;
        }
        if (finalSession && finalSession.n8nStatus === 'Failed') {
           isSuccess = false;
           break;
        }
      }

      // 3. Nếu lố 5 phút mà n8n im re chưa điền điểm, đánh dấu là Lỗi
      if (!isSuccess && (!finalSession || finalSession.n8nStatus === 'Processing')) {
         await sessionCol.updateOne(
           { batchId: batchId.toString(), studentName: studentDisplayName },
           { $set: { n8nStatus: 'Failed', errorDetails: 'Chờ quá 5 phút n8n vẫn chưa chấm xong.' } }
         );
      }
    }
  } catch (error) {
    const errorMessage = error.response ? `N8N Error ${error.response.status}: ${JSON.stringify(error.response.data)}` : error.message;
    console.error(`    [XO] Lỗi chấm bài ${studentDisplayName}:`, errorMessage);

    await sessionCol.updateOne(
      { batchId: batchId.toString(), studentName: studentDisplayName },
      {
        $set: {
          n8nStatus: 'Failed',
          errorDetails: errorMessage,
          updatedAt: new Date()
        }
      }
    );
    isSuccess = false;
  } finally {
    // Cập nhật tiến độ Batch
    await batchCol.updateOne(
      { _id: new ObjectId(batchId) },
      {
        $inc: {
          completedItems: isSuccess ? 1 : 0,
          failedItems: isSuccess ? 0 : 1
        },
        $set: { sheetUrl: batchSheetUrl }
      }
    );

    // Kiểm tra xem Batch này đã hoàn thành chưa
    const updatedBatch = await batchCol.findOne({ _id: new ObjectId(batchId) });
    if (updatedBatch && (updatedBatch.completedItems + updatedBatch.failedItems) >= updatedBatch.totalItems) {
      await batchCol.updateOne(
        { _id: new ObjectId(batchId) },
        { $set: { status: 'Completed', updatedAt: new Date() } }
      );
      console.log(`\x1b[32m[Batch ${batchId}]\x1b[0m Đã hoàn thành toàn bộ đợt chấm.`);

      // --- GỬI THÔNG BÁO HOÀN TẤT CHO GIÁO VIÊN (ĐỂ GỬI MAIL) ---
      try {
        const notifyUrl = webhookUrl.replace('magr-grading-webhook', 'magr-teacher-notification');
        await axios.post(notifyUrl, {
          event: 'GRADING_COMPLETED',
          receiver: 'TEACHER',
          batchId: batchId.toString(),
          batchName: updatedBatch.batchName,
          examInfo: {
            title: updatedBatch.examTitle,
            question: updatedBatch.questionTitle,
            examId: updatedBatch.examId
          },
          statistics: {
            total: updatedBatch.totalItems,
            success: updatedBatch.completedItems,
            failed: updatedBatch.failedItems
          },
          resultsUrl: batchSheetUrl,
          timestamp: new Date().toISOString()
        });
        console.log(`\x1b[32m[Teacher Notify]\x1b[0m Đã gửi báo cáo đợt chấm sang n8n (magr-teacher-notification).`);
      } catch (notifyError) {
        console.error(`\x1b[31m[Teacher Notify Error]\x1b[0m Thất bại khi gửi báo cáo:`, notifyError.message);
      }
    }

    // Tiếp tục xử lý bài tiếp theo trong hàng đợi
    processGlobalQueue();
  }
}

// --- NEW: Background Grading Batch ---

app.post('/api/grading/start-batch', async (req, res) => {
  const { examId, questionId, examTitle, questionTitle, submissionIds, webhookUrl, metadata, batchName } = req.body;

  if (!db) return res.status(503).json({ error: "Database not connected" });

  try {
    const batchCol = db.collection('grading_batches');

    // Automatic naming if empty
    let finalBatchName = (batchName || `${examTitle} - ${questionTitle}`).trim();

    // Unique naming logic (incrementing numbers if name exists)
    let uniqueName = finalBatchName;
    let counter = 1;
    while (await batchCol.findOne({ batchName: uniqueName, examId: examId, questionId: questionId })) {
      uniqueName = `${finalBatchName} (${counter++})`;
    }

    const batch = {
      batchName: uniqueName,
      examId,
      questionId,
      examTitle,
      questionTitle,
      totalItems: submissionIds.length,
      completedItems: 0,
      failedItems: 0,
      status: 'Processing',
      sheetUrl: metadata?.googleSheetId ? `https://docs.google.com/spreadsheets/d/${metadata.googleSheetId}` : null,
      createdAt: new Date()
    };

    const batchResult = await batchCol.insertOne(batch);
    const batchId = batchResult.insertedId;

    // --- TỐI ƯU HÓA: LẤY TẤT CẢ SUBMISSIONS TRONG 1 LẦN ---
    const subs = await db.collection('submissions').find({
      _id: { $in: submissionIds.map(id => new ObjectId(id)) }
    }).toArray();

    const pendingSessions = subs.map(sub => ({
      batchId: batchId.toString(),
      submissionId: sub._id.toString(),
      studentName: sub.studentName,
      studentImageBase64: sub.imageBase64,
      examId: sub.examId,
      questionId: sub.questionId,
      n8nStatus: 'Pending',
      createdAt: new Date()
    }));

    if (pendingSessions.length > 0) {
      await db.collection('gradings').insertMany(pendingSessions);
    }

    res.json({ batchId: batchId.toString() });

    addToGradingQueue(batchId, submissionIds, webhookUrl, metadata);

  } catch (e) {
    console.error("Failed to start batch:", e);
    res.status(500).json({ error: e.message });
  }
});

// Data API Action simulator
app.post('/action/:action', async (req, res) => {
  const { action } = req.params;
  const { collection: collectionName, filter, update, document, documents: docs, projection, sort, limit } = req.body;

  if (!db) return res.status(503).json({ error: "Database not connected" });

  try {
    const col = db.collection(collectionName);
    let result;

    // Handle $oid in filters/updates
    function processMongoJson(obj) {
      if (!obj || typeof obj !== 'object') return obj;

      if (obj.$oid) return new ObjectId(obj.$oid);

      for (const key in obj) {
        obj[key] = processMongoJson(obj[key]);
      }
      return obj;
    }

    const processedFilter = processMongoJson(filter);
    const processedUpdate = processMongoJson(update);
    const processedDoc = processMongoJson(document);

    switch (action) {
      case 'find':
        let query = col.find(processedFilter || {});
        if (projection) query = query.project(projection);
        if (sort) query = query.sort(sort);
        if (limit) query = query.limit(limit);
        const docsResult = await query.toArray();
        result = { documents: docsResult };
        break;

      case 'findOne':
        const oneDoc = await col.findOne(processedFilter || {});
        result = { document: oneDoc };
        break;

      case 'insertOne':
        const insertRes = await col.insertOne(processedDoc);
        result = { insertedId: insertRes.insertedId.toString() };
        break;

      case 'updateOne':
        const updateRes = await col.updateOne(processedFilter, processedUpdate);
        result = { matchedCount: updateRes.matchedCount, modifiedCount: updateRes.modifiedCount };
        break;

      case 'deleteOne':
        const deleteRes = await col.deleteOne(processedFilter);
        result = { deletedCount: deleteRes.deletedCount };
        break;

      case 'deleteMany':
        const delManyRes = await col.deleteMany(processedFilter);
        result = { deletedCount: delManyRes.deletedCount };
        break;

      default:
        return res.status(400).json({ error: "Unsupported action" });
    }

    res.json(result);
  } catch (e) {
    console.error(`Error in ${action}:`, e);
    res.status(500).json({ error: e.message });
  }
});

app.get('/', (req, res) => {
  res.send("MAGR Backend Bridge is running");
});

app.listen(port, () => {
  console.log(`Backend Bridge listening at http://localhost:${port}`);
});
