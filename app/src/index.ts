import 'reflect-metadata';
import { Hono } from 'hono';
import { serve } from '@hono/node-server';
import { AppDataSource } from './db/dataSource';
import todoRoutes from './routes/todoRoutes';

const app = new Hono();
const PORT = process.env.PORT || 3000;

app.get('/healthz', (c) => {
  return c.json({ status: 'healthy' }, 200);
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