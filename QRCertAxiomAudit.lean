import QRCertBlueprint
import QRCertWaveletFingerprint
import ReflectionKernel
import RamseyCertificate
import CustodyPolicy
import AgenticPayments

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

#print axioms QRCert.Wavelet.inverseButterfly_butterfly
#print axioms QRCert.Wavelet.inverse_forward
#print axioms QRCert.Wavelet.forward_injective
#print axioms QRCert.Wavelet.walshHadamard_injective
#print axioms QRCert.Wavelet.walshHadamard_energy
#print axioms QRCert.Wavelet.opBlockFingerprint_injective
#print axioms QRCert.Wavelet.compactOpBlockFingerprint_injective

#print axioms QRCert.Custody.Digest256.toWords_injective
#print axioms QRCert.Custody.checkApproval_eq_true_iff
#print axioms QRCert.Custody.checkAuthorization_eq_true_iff
#print axioms QRCert.Custody.checkAuthorization_sound
#print axioms QRCert.Custody.authorizeAndAdvance_eq_some_iff
#print axioms QRCert.Custody.authorizeAndAdvance_sound
#print axioms QRCert.Custody.example_authorization_sound

#print axioms QRCert.AgenticPayments.checkHumanApproval_eq_true_iff
#print axioms QRCert.AgenticPayments.checkPayment_eq_true_iff
#print axioms QRCert.AgenticPayments.authorizeAndAdvance_eq_some_iff
#print axioms QRCert.AgenticPayments.authorizeAndAdvance_sound
#print axioms QRCert.AgenticPayments.accepted_preserves_cumulative_budget
