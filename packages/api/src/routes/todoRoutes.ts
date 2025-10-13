import { Hono } from 'hono';
import { AppDataSource } from '../db/dataSource';
import { Todo } from '../models/Todo';

const app = new Hono();
const todoRepository = AppDataSource.getRepository(Todo);

app.get('/todos', async (c) => {
  try {
    const todos = await todoRepository.find({
      order: { createdAt: 'DESC' }
    });
    return c.json(todos);
  } catch (error) {
    return c.json({ error: 'Failed to fetch todos' }, 500);
  }
});

app.get('/todos/:id', async (c) => {
  try {
    const id = c.req.param('id');
    const todo = await todoRepository.findOne({
      where: { id: parseInt(id) }
    });
    if (!todo) {
      return c.json({ error: 'Todo not found' }, 404);
    }
    return c.json(todo);
  } catch (error) {
    return c.json({ error: 'Failed to fetch todo' }, 500);
  }
});

app.post('/todos', async (c) => {
  try {
    const { title, description } = await c.req.json();
    if (!title) {
      return c.json({ error: 'Title is required' }, 400);
    }
   
    const todo = todoRepository.create({
      title,
      description,
      completed: false
    });
    
    const result = await todoRepository.save(todo);
    return c.json(result, 201);
  } catch (error) {
    return c.json({ error: 'Failed to create todo' }, 500);
  }
});

app.put('/todos/:id', async (c) => {
  try {
    const id = parseInt(c.req.param('id'));
    const { title, description, completed } = await c.req.json();

    const todo = await todoRepository.findOne({ where: { id } });
    if (!todo) {
      return c.json({ error: 'Todo not found' }, 404);
    }

    if (title !== undefined) todo.title = title;
    if (description !== undefined) todo.description = description;
    if (completed !== undefined) todo.completed = completed;

    const result = await todoRepository.save(todo);
    return c.json(result);
  } catch (error) {
    return c.json({ error: 'Failed to update todo' }, 500);
  }
});

app.delete('/todos/:id', async (c) => {
  try {
    const id = parseInt(c.req.param('id'));
    const result = await todoRepository.delete(id);

    if (result.affected === 0) {
      return c.json({ error: 'Todo not found' }, 404);
    }

    return c.body(null, 204);
  } catch (error) {
    return c.json({ error: 'Failed to delete todo' }, 500);
  }
});

export default app;