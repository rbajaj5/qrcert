import QRCertWaveletFingerprint

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

#print axioms QRCert.Wavelet.inverseButterfly_butterfly
#print axioms QRCert.Wavelet.inverse_forward
#print axioms QRCert.Wavelet.forward_injective
#print axioms QRCert.Wavelet.walshHadamard_injective
#print axioms QRCert.Wavelet.walshHadamard_energy
#print axioms QRCert.Wavelet.opBlockFingerprint_injective
