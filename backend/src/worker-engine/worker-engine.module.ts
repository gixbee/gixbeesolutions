import { Module } from '@nestjs/common';
import { WorkerGateway } from './worker.gateway';

@Module({
  providers: [WorkerGateway],
})
export class WorkerEngineModule {}
