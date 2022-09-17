import { RouterContracts, RouterFactories } from '@abacus-network/sdk';

import { 
  HyperswapBridgeRouter,
  HyperswapBridgeRouter__factory,
  HyperswapCustodian,
  HyperswapCustodian__factory,
  HyperswapRouter,
  HyperswapRouter__factory,
} from '../types';

export type HyperswapFactories = RouterFactories<HyperswapBridgeRouter>;

export const hyperswapFactories: HyperswapFactories = {
  router: new HyperswapBridgeRouter__factory(),
  hyperswapRouter: new HyperswapRouter__factory(),
  hyperswapCustodian: new HyperswapCustodian__factory()
};

export type HyperswapContracts = RouterContracts<HyperswapBridgeRouter> & {
  hyperswapRouter: HyperswapRouter,
  hyperswapCustodian: HyperswapCustodian

};
