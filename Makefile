# shortcuts for calling common foundry commands

-include .env

# file to test 
FILE=

# specific test to run
TEST=

# block to test from 
BLOCK=16750165

# foundry test profile to run
PROFILE=$(TEST_PROFILE)

# forks from specific block 
FORK_BLOCK=--fork-block-number $(BLOCK)

# file to test
MATCH_PATH=--match-path src/test/$(FILE).t.sol

# test to run
MATCH_TEST=--match-test $(TEST)

# rpc url
FORK_URL=--fork-url https://eth-mainnet.alchemyapi.io/v2/$(ALCHEMY_API_KEY)

# generates and serves documentation locally on port 4000
docs_local :; forge doc --serve --port 4000

# generates and builds documentation to ./documentation
docs_build :; forge doc --build --out ./documentation

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