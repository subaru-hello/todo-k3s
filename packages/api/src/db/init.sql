-- Create todos table
CREATE TABLE IF NOT EXISTS todo (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    completed BOOLEAN DEFAULT FALSE,
    "createdAt" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_todo_completed ON todo(completed);
CREATE INDEX IF NOT EXISTS idx_todo_created_at ON todo("createdAt");

-- Insert some sample data for development
INSERT INTO todo (title, description, completed) VALUES 
    ('Setup development environment', 'Install Docker, Node.js, and other dependencies', true),
    ('Create API endpoints', 'Implement CRUD operations for todos', true),
    ('Add authentication', 'Implement JWT-based authentication', false),
    ('Write tests', 'Add unit and integration tests', false),
    ('Deploy to Kubernetes', 'Setup k3s cluster and deploy application', false)
ON CONFLICT DO NOTHING;