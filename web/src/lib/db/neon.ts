import { neon } from '@neondatabase/serverless';

const connectionString = process.env.IBEX_DATABASE_URL;
if (!connectionString) throw new Error('IBEX_DATABASE_URL is required');

export const sql = neon(connectionString);
