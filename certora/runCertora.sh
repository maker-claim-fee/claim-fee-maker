#!/usr/bin/env bash

# Script to run certora prover formal verification of Dss-Gate

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https:#www.gnu.org/licenses/>.

set -e

echo "Running Certora Prover for claim-fee-maker";

SOLC=~/.nix-profile/bin/solc-0.8.1

# Certora Prover Command Runner
certoraRun ../src/ClaimFee.sol:ClaimFee Vat.sol Gate1.sol \
         --link ClaimFee:vat=Vat ClaimFee:gate=Gate1 \
         --verify ClaimFee:ClaimFee.spec \
         --msg "$1"