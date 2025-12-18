## Main test runner - imports all test modules

import ./test_types
import ./test_variable
import ./test_key
import ./test_table

import ./test_relation
import ./test_model

import ./test_entropy

import ./test_statistics
import ./test_parser
import ./test_synthetic
import ./test_manager
import ./test_search
import ./test_integration
import ./test_complex
import ./test_converter
import ./test_loops
import ./test_binning

# E2E tests with UCI datasets
import ./e2e/test_uci_car
import ./e2e/test_uci_tictactoe
import ./e2e/test_uci_zoo
import ./e2e/test_uci_mushroom
import ./e2e/test_uci_nursery

# E2E tests with integer sequences (prime residue analysis)
import ./e2e/test_prime_residues
