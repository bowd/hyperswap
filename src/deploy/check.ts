import { AbacusRouterChecker, ChainName } from '@abacus-network/sdk';

import { HyperswapApp } from '../app/app';
import { HyperswapContracts } from '../app/contracts';

import { HyperswapConfig } from './config';

export class HyperswapChecker<
  Chain extends ChainName,
> extends AbacusRouterChecker<
  Chain,
  HyperswapApp<Chain>,
  HyperswapConfig,
  HyperswapContracts
> {}
