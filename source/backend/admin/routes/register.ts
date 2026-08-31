import { DatabaseSync } from 'node:sqlite';
import { Hono } from 'hono';
import { hashPassword } from '../../shared/password';
import { openApplicationDatabase } from '../../shared/schemaMigration';

export { hashPassword } from '../../shared/password';

type RegistrationData = {
  fullName: string;
  username: string;
  password: string;
};

type RegistrationRoutesOptions = {
  database?: DatabaseSync;
};

function validateBody(value: unknown):
  | { valid: true; data: RegistrationData }
  | { valid: false; fields: Record<string, string> } {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return { valid: false, fields: { body: 'Debe ser un objeto JSON.' } };
  }

  const body = value as Record<string, unknown>;
  const fullName = typeof body.fullName === 'string' ? body.fullName.trim() : '';
  const username =
    typeof body.username === 'string' ? body.username.trim().toLowerCase() : '';
  const password = typeof body.password === 'string' ? body.password : '';
  const fields: Record<string, string> = {};

  if (fullName.length < 2 || fullName.length > 100) {
    fields.fullName = 'Debe contener entre 2 y 100 caracteres.';
  }
  if (!/^[a-z0-9](?:[a-z0-9._-]{1,30}[a-z0-9])?$/.test(username)) {
    fields.username =
      'Debe contener entre 3 y 32 caracteres: letras, números, punto, guion o guion bajo.';
  }
  if (password.length < 12 || password.length > 128) {
    fields.password = 'Debe contener entre 12 y 128 caracteres.';
  }

  if (Object.keys(fields).length > 0) return { valid: false, fields };
  return { valid: true, data: { fullName, username, password } };
}

export function createAdminRegistrationRoutes(
  options: RegistrationRoutesOptions = {},
): Hono {
  const routes = new Hono();
  let database = options.database;
  const getDatabase = () => {
    database ??= openApplicationDatabase();
    return database;
  };

  routes.post('/register', async (c) => {
    const contentType = c.req.header('content-type')?.toLowerCase() ?? '';
    if (!contentType.startsWith('application/json')) {
      return c.json(
        { error: 'UNSUPPORTED_MEDIA_TYPE', message: 'Use application/json.' },
        415,
      );
    }

    let body: unknown;
    try {
      body = await c.req.json<unknown>();
    } catch {
      return c.json(
        { error: 'INVALID_JSON', message: 'El cuerpo JSON no es válido.' },
        400,
      );
    }

    const validation = validateBody(body);
    if (!validation.valid) {
      return c.json(
        {
          error: 'VALIDATION_ERROR',
          message: 'Los datos de registro no son válidos.',
          fields: validation.fields,
        },
        422,
      );
    }

    const db = getDatabase();
    const duplicate = db
      .prepare('SELECT 1 FROM users WHERE username = ? LIMIT 1')
      .get(validation.data.username);
    if (duplicate !== undefined) {
      return c.json(
        {
          error: 'USERNAME_TAKEN',
          message: 'El nombre de usuario ya está registrado.',
        },
        409,
      );
    }

    const passwordHash = await hashPassword(validation.data.password);
    try {
      const result = db.prepare(
        `INSERT INTO users (name, role, username, password_hash)
         VALUES (?, 'admin', ?, ?)`,
      ).run(
        validation.data.fullName,
        validation.data.username,
        passwordHash,
      );
      const admin = {
        id: Number(result.lastInsertRowid),
        fullName: validation.data.fullName,
        username: validation.data.username,
        role: 'admin' as const,
      };
      return c.json({ admin }, 201);
    } catch (error) {
      const message = error instanceof Error ? error.message : '';
      if (message.includes('UNIQUE constraint failed')) {
        return c.json(
          {
            error: 'USERNAME_TAKEN',
            message: 'El nombre de usuario ya está registrado.',
          },
          409,
        );
      }
      console.error('No se pudo registrar el administrador:', error);
      return c.json(
        { error: 'INTERNAL_ERROR', message: 'No se pudo crear la cuenta.' },
        500,
      );
    }
  });

  return routes;
}

export default createAdminRegistrationRoutes();
