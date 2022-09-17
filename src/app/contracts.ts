import { RouterContracts, RouterFactories } from '@abacus-network/sdk';

import { 
  HyperswapBridgeRouter,
  HyperswapBridgeRouter__factory,
} from '../types';

export type HyperswapFactories = RouterFactories<HyperswapBridgeRouter>;

export const helloWorldFactories: HyperswapFactories = {
  router: new HyperswapBridgeRouter__factory()
};

export type HyperswapContracts = RouterContracts<HyperswapBridgeRouter>;
