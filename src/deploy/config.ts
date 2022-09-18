import { RouterConfig, chainConnectionConfigs } from "@abacus-network/sdk";

export type HyperswapConfig = RouterConfig;

// SET DESIRED NETWORKS HERE
export const prodConfigs = {
  alfajores: chainConnectionConfigs.alfajores,
  goerli: chainConnectionConfigs.goerli,
};
