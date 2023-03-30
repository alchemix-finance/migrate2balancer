# Alchemix Sushi to Balancer LP Migrator

## About

Migrator.sol facilitates migrating Sushi LPs to an 80/20 Balancer LP with the option to deposit directly into an Aura pool.

-   SLP: SushiSwap LP Token
-   BPT: 20WETH-80TOKEN Balancer Pool Token
-   auraBPT: 20WETH-80TOKEN Aura Deposit Vault
-   The entire SLP balance of `msg.sender` is migrated
-   Users should pass `migrate(bool _stakeBpt)` a boolean to indicate if migrated BPT should be staked in Aura
-   The Migrator will unwrap the SLP, swap the 50/50 TOKEN/WETH balance for an 80/20 TOKEN/WETH balance, deposit the tokens into a Balancer pool, and either deposit the BPT tokens into an Aura pool sending `msg.sender` auraBPT, or transfer the BPT directly to the `msg.sender`

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
