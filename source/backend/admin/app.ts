import { Hono } from 'hono';
import { logger } from 'hono/logger';
import adminRegistrationRoutes from './routes/register';
import adminSessionRoutes from './routes/session';
import adminPairDeviceRoutes from './routes/pairDevice';
import adminEmployeeRoutes from './routes/employees';
import adminLayoutRoutes from './routes/layout';
import adminCatalogRoutes from './routes/catalog';
import adminActivityRoutes from './routes/activity';

// Las rutas administrativas se montarán únicamente en esta aplicación para
// impedir que se expongan accidentalmente en el listener de la red local.
const adminApp = new Hono();

adminApp.use('*', logger());

adminApp.get('/', (c) => {
  return c.text('Servidor administrativo funcionando');
});

adminApp.route('/api/admin', adminRegistrationRoutes);
adminApp.route('/api/admin', adminSessionRoutes);
adminApp.route('/api/admin', adminPairDeviceRoutes);
adminApp.route('/api/admin', adminEmployeeRoutes);
adminApp.route('/api/admin', adminLayoutRoutes);
adminApp.route('/api/admin', adminCatalogRoutes);
adminApp.route('/api/admin', adminActivityRoutes);

export default adminApp;
