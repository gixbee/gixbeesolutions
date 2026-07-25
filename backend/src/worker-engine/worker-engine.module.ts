import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { WorkerGateway } from './worker.gateway';

@Module({
  imports: [AuthModule],
  providers: [WorkerGateway],
})
export class WorkerEngineModule {}
