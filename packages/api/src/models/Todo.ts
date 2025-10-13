// src/models/Todo.ts
import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn } from 'typeorm';

@Entity('todos')
export class Todo {
  @PrimaryGeneratedColumn()
  id!: number;

  // ★ 型を明示
  @Column({ type: 'varchar', length: 255 })
  title!: string;

  @Column({ type: 'text', nullable: true })
  description?: string;

  // ★ boolean も明示
  @Column({ type: 'boolean', default: false })
  completed!: boolean;

  // DBに合わせて（Postgresなら timestamptz 推奨。未指定でも多くは動く）
  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt!: Date;
}

