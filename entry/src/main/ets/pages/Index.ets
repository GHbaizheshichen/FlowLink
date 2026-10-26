import { common } from '@kit.AbilityKit';
import { AppRoute } from '../navigation/AppRoute';
import { ProxyAppState } from '../state/ProxyAppState';
import { ProxyAppController } from '../state/ProxyAppController';
import { HomePage } from './HomePage';
import { NodePage } from './NodePage';
import { SubscriptionPage } from './SubscriptionPage';
import { AddSubscriptionPage } from './AddSubscriptionPage';
import { ModePage } from './ModePage';
import { SettingsPage } from './SettingsPage';
import { ProxyNode } from '../subscription/ProxyNode';

@Entry
@ComponentV2
struct Index {
  @Local private state: ProxyAppState = new ProxyAppState();
  private controller: ProxyAppController = new ProxyAppController(this.state);
  private pathStack: NavPathStack = new NavPathStack();

  private showRoot(route: AppRoute): void {
    if (this.pathStack.getAllPathName()[0] === route && this.pathStack.size() === 1) { return; }
    this.pathStack.replacePath({ name: route }, false);
  }

  aboutToAppear(): void {
    if (this.pathStack.size() === 0) {
      this.pathStack.pushPath({ name: AppRoute.HOME }, false);
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.controller.initialize(context);
  }

  @Builder
  destination(name: string) {
    if (name === AppRoute.HOME) {
      HomePage({
        state: this.state,
        onNavigate: (route: AppRoute) => this.showRoot(route),
        onOpenNodes: () => this.showRoot(AppRoute.NODES),
        onOpenSubscription: () => this.showRoot(AppRoute.SUBSCRIPTIONS),
        onOpenMode: () => this.pathStack.pushPath({ name: AppRoute.MODE }),
        onConnect: () => this.controller.explainConnection()
      })
    } else if (name === AppRoute.NODES) {
      NodePage({
        state: this.state,
        onTest: (nodes: ProxyNode[]) => this.controller.toggleLatency(nodes),
        onNavigate: (route: AppRoute) => this.showRoot(route),
        onSelect: (id: string) => {
          this.controller.selectNode(id);
          if (this.state.selectedNodeId === id) { this.showRoot(AppRoute.HOME); }
        },
        onOpenSubscription: () => this.showRoot(AppRoute.SUBSCRIPTIONS)
      })
    } else if (name === AppRoute.SUBSCRIPTIONS) {
      SubscriptionPage({
        state: this.state,
        onNavigate: (route: AppRoute) => this.showRoot(route),
        onAdd: () => this.pathStack.pushPath({ name: AppRoute.ADD_SUBSCRIPTION }),
        onUpdate: () => { this.controller.saveSubscription(this.state.subscriptionAddress); },
        onClear: () => this.controller.clearSubscription()
      })
    } else if (name === AppRoute.ADD_SUBSCRIPTION) {
      AddSubscriptionPage({ state: this.state, onBack: () => { this.pathStack.pop(); },
        onSave: (address: string, title: string) => this.controller.saveSubscription(address, title) })
    } else if (name === AppRoute.MODE) {
      ModePage({ state: this.state, onBack: () => { this.pathStack.pop(); } })
    } else if (name === AppRoute.SETTINGS) {
      SettingsPage({ state: this.state, onNavigate: (route: AppRoute) => this.showRoot(route) })
    }
  }

  build() {
    Navigation(this.pathStack) {
    }
    .mode(NavigationMode.Stack)
    .hideNavBar(true)
    .navDestination(this.destination)
    .backgroundColor($r('app.color.page_background'))
    .width('100%')
    .height('100%')
  }
}
