import { RouterContracts, RouterFactories } from '@abacus-network/sdk';

import { 
  HyperswapBridgeRouter,
  HyperswapBridgeRouter__factory,
  HyperswapCustodian,
  HyperswapRouter,
} from '../types';

export type HyperswapFactories = RouterFactories<HyperswapBridgeRouter>;

export const hyperswapFactories: HyperswapFactories = {
  router: new HyperswapBridgeRouter__factory(),
};

export type HyperswapContracts = RouterContracts<HyperswapBridgeRouter> & {
  hyperswapRouter: HyperswapRouter,
  hyperswapCustodian: HyperswapCustodian
};
