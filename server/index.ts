import dotenv from 'dotenv';
import express from 'express';
import cors from 'cors';
import pino from 'pino';
import pinoHttp from 'pino-http';
import jobsRouter from './routes/jobs';
import searchRouter from './routes/search';

dotenv.config();

const app = express();
const port = process.env.PORT || 8800;
const logger = pino();

// Middleware
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(pinoHttp({ logger }));

// Routes
app.use('/api', jobsRouter);
app.use('/api', searchRouter);

// Health check
app.get('/healthz', (req, res) => {
  res.json({ ok: true });
});

app.listen(port, () => {
  logger.info(`Server running on port ${port}`);
});