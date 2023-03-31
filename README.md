# Alchemix UniV2 50/50 LP to Balancer 80/20 LP Migrator

## About

Migrator.sol facilitates migrating LPs to an 80/20 Balancer LP with the option to deposit directly into an Aura pool.

-   LP: IUniswapV2Pair LP Token
-   BPT: 20WETH-80TOKEN Balancer Pool Token
-   auraBPT: 20WETH-80TOKEN Aura Deposit Pool
-   The entire LP balance of `msg.sender` is migrated
-   See `IMigrator.sol` for the structs required when migrating
-   See `BaseTest.sol` for examples of the off-chain calculations that need to be made when calling `migrate()`
-   The Migrator will unwrap an LP, swap the 50/50 TOKEN/WETH balance for an 80/20 TOKEN/WETH balance, deposit Tokens and WETH into a Balancer pool, and either deposit the BPT tokens into an Aura pool sending `msg.sender` auraBPT, or transfer the BPT directly to the `msg.sender`

## Getting Started

### Create a `.env` file with the following environment variables

```
ALCHEMY_API_KEY=<alchemy api key>
TEST_PROFILE=default
```

### Install latest version of foundry

`curl -L https://foundry.paradigm.xyz | bash`

### Install dependencies

`forge install`

## Testing

### Run all foundry tests at specific block

`make test_block`

### Run all foundry tests at current block

`make test_all`

### Coverage report in terminal

`make test_summary`

### Coverage report lcov file

`make test_coverage`

## Documentation

### on localhost

Generate natspec documentation locally with `make docs_local`

### to ouput file

Generate and build documentation to ./documentation with `make docs_build`
