import { MigrationInterface, QueryRunner } from 'typeorm';

/// Append-only audit trail for master-data and restricted settings mutations.
export class MasterDataAudit1756400000000 implements MigrationInterface {
  name = 'MasterDataAudit1756400000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS master_data_audit (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        section varchar NOT NULL,
        "entityType" varchar NOT NULL,
        "entityId" varchar NOT NULL,
        action varchar NOT NULL,
        "actorUserId" uuid NOT NULL,
        "beforeJson" jsonb,
        "afterJson" jsonb,
        "createdAt" timestamptz NOT NULL DEFAULT NOW()
      )`);
    await queryRunner.query(
      `CREATE INDEX IF NOT EXISTS master_data_audit_section_created ON master_data_audit (section, "createdAt" DESC)`,
    );
    await queryRunner.query(
      `CREATE INDEX IF NOT EXISTS master_data_audit_entity ON master_data_audit ("entityType", "entityId")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE IF EXISTS master_data_audit`);
  }
}
