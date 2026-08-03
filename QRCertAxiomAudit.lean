import QRCertBlueprint
import ReflectionKernel
import RamseyCertificate

/-!
Run with:

  lake env lean -E warning QRCertAxiomAudit.lean

This reports the axioms used by the central blueprint theorems.  It is
separate from the library build so that audit output remains visible in CI.
-/

#print axioms QRCert.Blueprint.checkOp_refines
#print axioms QRCert.Blueprint.parseOp_refines
#print axioms QRCert.Blueprint.parseOps_refines
#print axioms QRCert.Blueprint.deserialize_refines
#print axioms QRCert.Blueprint.deserializeSpec_encode_of_fixedByteEncodable
#print axioms QRCert.Blueprint.deserializeSpec_accepted_canonical
#print axioms QRCert.Blueprint.deserialize_injective
#print axioms QRCert.Blueprint.deserialize_implies_WellFormed
#print axioms QRCert.Blueprint.costExtractedModel_sound
#print axioms QRCert.Blueprint.costExtractedModel_success_agrees
#print axioms QRCert.Blueprint.deserializeSpec_implies_cost_success
#print axioms QRCert.Reflection.verifyResourceClaim_sound
#print axioms QRCert.Reflection.validCCX_claim_sound
#print axioms QRCert.Ramsey.mem_words_iff
#print axioms QRCert.Ramsey.noMonochromaticCliqueB_refines
#print axioms QRCert.Ramsey.verify_sound
#print axioms QRCert.Ramsey.cycle5_certificate_sound
