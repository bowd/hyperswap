import {
  HyperswapBridgeRouter,
  HyperswapBridgeRouter__factory,
  HyperswapCustodian,
  HyperswapRouter,
} from "../types";
import { RouterContracts, RouterFactories } from "@abacus-network/sdk";

export type HyperswapFactories = RouterFactories<HyperswapBridgeRouter>;

export const hyperswapFactories: HyperswapFactories = {
  router: new HyperswapBridgeRouter__factory(),
};

export type HyperswapContracts = RouterContracts<HyperswapBridgeRouter> & {
  hyperswapRouter: HyperswapRouter;
  hyperswapCustodian: HyperswapCustodian;
};
