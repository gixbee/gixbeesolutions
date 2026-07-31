import { MigrationInterface, QueryRunner } from 'typeorm';

export class RemoveGoLiveMinWallet1753400000001 implements MigrationInterface {
  name = 'RemoveGoLiveMinWallet1753400000001';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `DELETE FROM "master_entries" WHERE "label" = 'go_live_min_wallet'`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    // We do not restore the default value since it is no longer used.
  }
}
