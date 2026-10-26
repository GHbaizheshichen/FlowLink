import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

// UI-process storage only. Do not use this instance for VPN-process messaging.
export class SubscriptionRepository {
  private store?: preferences.Preferences;

  async initialize(context: common.UIAbilityContext): Promise<void> {
    try {
      this.store = await preferences.getPreferences(context, { name: 'harmony_proxy_settings' });
    } catch {
      throw new Error('STORAGE_INIT_FAILED');
    }
  }

  async readAddress(): Promise<string> {
    try {
      return await this.requireStore().get('subscription_address', '') as string;
    } catch {
      throw new Error('STORAGE_READ_FAILED');
    }
  }

  async saveAddress(address: string): Promise<void> {
    try {
      const store = this.requireStore();
      await store.put('subscription_address', address);
      await store.flush();
    } catch {
      throw new Error('STORAGE_WRITE_FAILED');
    }
  }

  async readName(): Promise<string> {
    try { return await this.requireStore().get('subscription_name', '') as string; }
    catch { throw new Error('STORAGE_READ_FAILED'); }
  }

  async saveName(name: string): Promise<void> {
    try {
      const store = this.requireStore();
      await store.put('subscription_name', name);
      await store.flush();
    } catch { throw new Error('STORAGE_WRITE_FAILED'); }
  }

  private requireStore(): preferences.Preferences {
    if (!this.store) {
      throw new Error('STORAGE_NOT_READY');
    }
    return this.store;
  }
}
