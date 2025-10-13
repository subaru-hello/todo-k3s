import 'reflect-metadata';
import { Hono } from 'hono';
import { serve } from '@hono/node-server';
import { cors } from 'hono/cors';
import { AppDataSource } from './db/dataSource';
import todoRoutes from './routes/todoRoutes';

const app = new Hono();
const PORT = process.env.PORT || 3000;

// CORS設定
const allowedOrigins = process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:5173'];
app.use('/*', cors({
  origin: allowedOrigins,
  credentials: true,
}));

app.get('/healthz', (c) => {
  return c.json({ status: 'healthy' }, 200);
});

app.get('/dbcheck', async (c) => {
  try {
    await AppDataSource.query('SELECT NOW() as now');
    return c.json({ status: 'ok', db: 'connected' }, 200);
  } catch (error: any) {
    return c.json({ status: 'error', message: error?.message || 'Database connection failed' }, 500);
  }
});

app.route('/api', todoRoutes);

AppDataSource.initialize()
  .then(() => {
    console.log('Database connected successfully');
    
    serve({
      fetch: app.fetch,
      port: Number(PORT)
    });
    
    console.log(`Server is running on port ${PORT}`);
  })
  .catch((error) => {
    console.error('Error connecting to database:', error);
    process.exit(1);
  });