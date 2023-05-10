# Alchemix UniV2 50/50 LP to Balancer 80/20 LP Migrator

## About

Migrator.sol facilitates migrating UniV2 LPs to an 80/20 Balancer LP with the option to deposit directly into an Aura pool.

-   LP: UniV2 LP Token
-   BPT: 20WETH-80TOKEN Balancer Pool Token
-   auraBPT: 20WETH-80TOKEN Aura Deposit Pool
-   See `MigrationCalcs.sol` for the calculations that need to be made and passed into `migrate()`
-   The calculations or output of `getMigrationParams()` should be used as values for `MigrationParams` in `IMigrator.sol`
-   The Migrator will unwrap the UniV2 LP tokens, rebalance the 50/50 TOKEN/WETH balance to an 80/20 TOKEN/WETH balance by swapping extra WETH for TOKEN, deposit the rebalanced 80/20 TOKEN/WETH amount into a Balancer pool, and either deposit the newly minted BPT tokens into an Aura pool sending `msg.sender` auraBPT, or transfer the BPT directly to the `msg.sender`

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
