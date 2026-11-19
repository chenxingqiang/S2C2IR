#!/usr/bin/env python3
"""Shared constants for the S2C2IR Python host stack.

Single source for the identity, action, and ledger literals that
the host modules previously held as per-module literal copies.
The values are frozen by the lit tests and by
record_constant_audit.py; changing one here still requires the
frozen contracts to stay green. Query only. No semantic cut.
can-run-plan stays no.
"""

from __future__ import annotations

# Decision-chain schemas.
DECISION_SCHEMA = "s2c2.decision.v1"
AUTH_SCHEMA = "s2c2.authorization.v1"
SUFFICIENCY_SCHEMA = "s2c2.sufficiency.v1"
REWRITE_SCHEMA = "s2c2.storage_rewrite.v1"
APPLY_SCHEMA = "s2c2.storage_apply.v1"
WITNESS_SCHEMA = "s2c2.apply_legality_witness.v1"

# Action identity: (selected, object, action).
SELECTED_S0 = "keep{0,1}|evict{2}|rematerialize{}"
SELECTED_S1 = "keep{1,2}|evict{0}|rematerialize{}"
OBJECT_2 = "2"
OBJECT_3 = "3"
ACTION_V01 = "storage-rewrite"
LICENSE_KIND_V01 = "storage-capacity-rewrite"

# Authorization policy v0.1.
POLICY_V01 = "authorization-policy-v0.1"
LICENSE_SUBJECT = "rewrite-license"

# Rewrite sequence v0.1.
SEQUENCE_SUBJECT = "rewrite-sequence"
SEQUENCE_V01 = ("KEEP", "EVICT", "TRANSFER", "RESTORE")
TRANSFORMATION_V01 = "keep-evict-transfer-restore"

# Hardware ledger vocabulary.
LEDGER_HARDWARE = ("rtx4090", "ascend910b")
LEDGER_KIND = ("catalog", "overlay", "campaign", "program")
LEDGER_STATUS = ("measured", "device-absent")
LEDGER_TOOL = ("cuda", "ascend", "none")
