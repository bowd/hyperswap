# Hyperswap

A permissionless cross-chain AMM based on UniswapV2 and [Hyperlane](https://hyperlane.xyz/).

## Components

### HyperswapBridgeRouter

Part of the Hyperlane implementation, it intermediates the sending of messages cross-chain.

### HyperswapRouter

Based on the UniswapV2 Router, it allows users to:

- Create a Cross-chain pairs and add liquidity to them
- Remove liquidity from cross-chain pairs
- Swap on cross-chain pairs

This is done via `Seqeuences` which are a way of tracking cross-chain operations as a simple state-machine and which record sufficient data in order to recover from potential bridge failures.

> Recovery hasn't been implemented but it has been explored and all the end-states of the state machine for each sequence are recoverable.

The HyperswapRouter lives on the chain where the pool states will be managed, also known as the `Hub` chain.

### HypserswapFactory

Based on the UniswapV2 Factory, it's used by the HypserswapRouter to create pairs.
It deployed a dummy AccountingERC20 via the ProxyTokenFactory which is used as an intermediary for the Remote token in the pair.

### HyperswapCustodian

Deployed on one or more `Spoke` chains, it custodies pool assets for the `Hub` chain.
For example if we have an AVAX/ETH pool on Avalanche, a HyperswapCustodian will be deployed on Ethereum to hold the ETH in the pool, receive deposits and pay out swaps or withdrawals.

### HyperswapPair

BAsed on the UniswapV2 Pair, it's a Pair that supports a local and remote Token.

## Setup

```sh
# Install dependencies
yarn

# Build source and generate types
yarn build
```

## Test

```sh
# Run all unit tests
forge test -vvvv

# Lint check code
yarn lint
```