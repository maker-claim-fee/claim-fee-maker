all             :; dapp build
clean           :; dapp clean && rm -rf ./echidna/crytic-export
                    # Usage example: make test match=Close
test            :; make && ./test-cfm.sh $(match)
deploy          :; make && dapp create ClaimFee $(gate)

# Echidna Testing - ALL TESTs Invariants ( access + conditional + functional)
echidna-claimfee :; ./echidna/runner/echidna-invariants.sh

# Echidna Testing - Conditional Invariants ONLY
echidna-claimfee-conditional :; ./echidna/runner/echidna-conditional-invariants.sh

# Echidna Testing - Functional Invariants ONLY
echidna-claimfee-functional :; ./echidna/runner/echidna-functional-invariants.sh
