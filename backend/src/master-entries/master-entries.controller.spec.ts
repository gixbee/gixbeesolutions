import { MasterEntriesController } from './master-entries.controller';
import { MasterEntryType } from './master-entry.entity';

/**
 * Unit tests for the MasterEntriesController HTTP layer — a thin delegation over
 * MasterEntriesService whose one piece of real logic is the `isActive` query-param
 * coercion ('true'/'false' string → boolean, anything else → undefined). Guards on
 * the write routes (JwtAuthGuard + AdminGuard) are metadata-only at this layer and
 * are exercised by admin.guard.spec.ts / e2e; here we assert request→service
 * delegation and the param coercion. Instantiated directly with a jest-mock service
 * (this repo's controller-spec style — no Nest TestingModule, no DB/network).
 */

function makeController() {
  const service: any = {
    create: jest.fn(async (data: any) => ({ id: 'm1', ...data })),
    findAll: jest.fn(async () => [{ id: 'm1' }, { id: 'm2' }]),
    findOne: jest.fn(async () => ({ id: 'm1' })),
    update: jest.fn(async () => ({ id: 'm1', label: 'Updated' })),
    remove: jest.fn(async () => undefined),
  };
  const controller = new MasterEntriesController(service);
  return { controller, service };
}

describe('MasterEntriesController.create', () => {
  it('passes the body straight through to service.create', async () => {
    const { controller, service } = makeController();
    const body = { type: MasterEntryType.DEAL, label: '20% off', value: 'deal20', icon: '🔥' };
    const res = await controller.create(body);
    expect(service.create).toHaveBeenCalledWith(body);
    expect(res).toEqual({ id: 'm1', ...body });
  });
});

describe('MasterEntriesController.findAll (query-param coercion)', () => {
  it("coerces isActive='true' to boolean true", async () => {
    const { controller, service } = makeController();
    await controller.findAll(MasterEntryType.BANNER, 'true');
    expect(service.findAll).toHaveBeenCalledWith(MasterEntryType.BANNER, true);
  });

  it("coerces isActive='false' to boolean false", async () => {
    const { controller, service } = makeController();
    await controller.findAll(MasterEntryType.BANNER, 'false');
    expect(service.findAll).toHaveBeenCalledWith(MasterEntryType.BANNER, false);
  });

  it('leaves isActive undefined when the param is omitted', async () => {
    const { controller, service } = makeController();
    await controller.findAll(MasterEntryType.CATEGORY, undefined);
    expect(service.findAll).toHaveBeenCalledWith(MasterEntryType.CATEGORY, undefined);
  });

  it('treats any non-true/false isActive string as undefined (not falsey-coerced)', async () => {
    const { controller, service } = makeController();
    await controller.findAll(undefined, 'yes');
    expect(service.findAll).toHaveBeenCalledWith(undefined, undefined);
  });

  it('forwards an undefined type filter unchanged (public consumer read)', async () => {
    const { controller, service } = makeController();
    const res = await controller.findAll(undefined, undefined);
    expect(service.findAll).toHaveBeenCalledWith(undefined, undefined);
    expect(res).toEqual([{ id: 'm1' }, { id: 'm2' }]);
  });
});

describe('MasterEntriesController.findOne', () => {
  it('forwards the URL :id to service.findOne', async () => {
    const { controller, service } = makeController();
    const res = await controller.findOne('m-42');
    expect(service.findOne).toHaveBeenCalledWith('m-42');
    expect(res).toEqual({ id: 'm1' });
  });
});

describe('MasterEntriesController.update', () => {
  it('forwards :id + the patch body to service.update', async () => {
    const { controller, service } = makeController();
    const body = { label: 'Updated', isActive: false };
    await controller.update('m-42', body);
    expect(service.update).toHaveBeenCalledWith('m-42', body);
  });
});

describe('MasterEntriesController.remove', () => {
  it('forwards :id to service.remove', async () => {
    const { controller, service } = makeController();
    await controller.remove('m-42');
    expect(service.remove).toHaveBeenCalledWith('m-42');
  });
});
