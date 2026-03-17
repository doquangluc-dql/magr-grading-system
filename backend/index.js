const express = require('express');
const cors = require('cors');
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const app = express();
const port = process.env.PORT || 3000;

app.use(cors());
app.use(express.json({ limit: '50mb' }));

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
