# shortcuts for calling common foundry commands

-include .env

# specific file 
FILE=

# specific test to run
TEST=

# block to test from 
BLOCK=17230496

# foundry test profile to run
PROFILE=$(TEST_PROFILE)

# forks from specific block 
FORK_BLOCK=--fork-block-number $(BLOCK)

# file to test
MATCH_PATH=--match-path test/$(FILE).t.sol

# test to run
MATCH_TEST=--match-test $(TEST)

# Mainnet rpc url
RPC=https://eth-mainnet.alchemyapi.io/v2/$(ALCHEMY_API_MAINNET_KEY)

# Sepolia rpc url 
TESTNET_RPC=https://sepolia.infura.io/v3/$(INFURA_API_KEY)

# fork from rpc
FORK_URL=--fork-url $(RPC)

# generates and serves documentation locally on port 4000
docs_local :; forge doc --serve --port 4000

# generates and builds documentation to ./docs
docs_build :; forge doc --build --out ./docs

# runs all tests: "make test_all"
test_all :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL)

# runs all tests from a given block (setting block is optional): "make test_block BLOCK=16750165"
test_block :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL) $(FORK_BLOCK)

# runs test coverage: "make test_coverage" add "--report lcov" to use with lcov reporter
test_coverage :; FOUNDRY_PROFILE=$(PROFILE) forge coverage $(FORK_URL) --report lcov

# runs test coverage: "make test_summary" to get output in terminal
test_summary :; FOUNDRY_PROFILE=$(PROFILE) forge coverage $(FORK_URL) --report summary

# runs test coverage for specific file: "make test_summary_file FILE=<filename>" to use with lcov reporter
test_coverage_file :; FOUNDRY_PROFILE=$(PROFILE) forge coverage $(FORK_URL) $(MATCH_PATH) --report lcov

# runs test coverage for specific file: "make test_summary_file FILE=<filename>"
test_summary_file :; FOUNDRY_PROFILE=$(PROFILE) forge coverage $(FORK_URL) $(MATCH_PATH) --report summary

# runs all tests with added verbosity for failing tests: "make test_debug"
test_debug :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL) -vvv

# runs specific test file with console logs: "make test_file FILE=<filename>"
test_file :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL) $(MATCH_PATH) -vv

# runs specific test file with added verbosity for failing tests: "make test_file_debug FILE=<filename>"
test_file_debug :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL) $(MATCH_PATH) -vvv

# runs specific test file from a given block (setting block is optional): "make test_file_block FILE=<filename>"
test_file_block :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL) $(MATCH_PATH) $(FORK_BLOCK)

# runs specific test file with added verbosity for failing tests from a given block: "make test_file_block_debug FILE=<filename>"
test_file_block_debug :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL) $(MATCH_PATH) $(FORK_BLOCK) -vvv

# runs single test within file with added verbosity for failing test: "make test_file_debug_test FILE=<filename> TEST=<testname>"
test_file_debug_test :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL) $(MATCH_PATH) $(MATCH_TEST) -vvv

# runs single test within file with added verbosity for failing test from a given block: "make test_file_block_debug_test FILE=<filename> TEST=<testname>"
test_file_block_debug_test :; FOUNDRY_PROFILE=$(PROFILE) forge test $(FORK_URL) $(MATCH_PATH) $(MATCH_TEST) $(FORK_BLOCK) -vvv


# shortcuts for deploying contracts

# add constructor args as needed (weth, balancer vault, sushi router)
ARGS=--constructor-args 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 0xBA12222222228d8Ba445958a75a0704d566BF2C8 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F

# etherscan verification
VERIFY=--etherscan-api-key $(ETHERSCAN_API_KEY) --verify

# private key for deployment
KEY=--private-key $(PRIVATE_KEY)

# Mainnet deployment command
DEPLOY_MAINNET=--rpc-url $(RPC) $(ARGS) $(KEY) $(VERIFY) src/$(FILE).sol:$(FILE)

# Sepolia deployment command
DEPLOY_SEPOLIA=--rpc-url $(TESTNET_RPC) $(ARGS) $(KEY) $(VERIFY) src/$(FILE).sol:$(FILE)

# Deploy a contract to mainnet (assumes file and contract name match) "make deploy_mainnet FILE=<filename>"
deploy_mainnet :; forge create $(DEPLOY_MAINNET)

# Deploy a contract to sepolia (assumes file and contract name match) "make deploy_sepolia FILE=<filename>"
deploy_sepolia :; forge create $(DEPLOY_SEPOLIA)