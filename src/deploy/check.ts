import { HyperswapApp } from "../app/app";
import { HyperswapContracts } from "../app/contracts";
import { HyperswapConfig } from "./config";
import { AbacusRouterChecker, ChainName } from "@abacus-network/sdk";

export class HyperswapChecker<
  Chain extends ChainName
> extends AbacusRouterChecker<
  Chain,
  HyperswapApp<Chain>,
  HyperswapConfig,
  HyperswapContracts
> {}
