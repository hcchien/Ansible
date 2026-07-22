package hostedissuer

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"math/big"
	"time"

	"github.com/go-webauthn/webauthn/webauthn"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PostgresStore struct {
	pool *pgxpool.Pool
}

func NewPostgresStore(pool *pgxpool.Pool) *PostgresStore { return &PostgresStore{pool: pool} }

func (s *PostgresStore) BootstrapTenant(tenant Tenant, owner Administrator) error {
	if tenant.AdministratorCount == 0 {
		tenant.AdministratorCount = tenant.Threshold
	}
	if tenant.ID == "" || tenant.OrganizationDID == "" || tenant.ServiceSlug == "" || tenant.Threshold < 1 ||
		owner.DID == "" || owner.Custody != "hardware" || owner.SigningAlgorithm != "p256-sha256" {
		return ErrDelegationInvalid
	}
	tx, err := s.pool.Begin(context.Background())
	if err != nil {
		return err
	}
	defer tx.Rollback(context.Background()) //nolint:errcheck
	if _, err = tx.Exec(context.Background(), `
		INSERT INTO issuer_tenants
			(id, organization_did, service_slug, status, approval_threshold, administrator_count, policy_version, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`, tenant.ID, tenant.OrganizationDID, tenant.ServiceSlug,
		tenant.Status, tenant.Threshold, tenant.AdministratorCount, tenant.PolicyVersion, tenant.CreatedAt); err != nil {
		return err
	}
	if _, err = tx.Exec(context.Background(), `
		INSERT INTO issuer_administrators
			(tenant_id, admin_did, role, state, signing_algorithm, public_key_hex, custody)
		VALUES ($1,$2,'owner','active',$3,$4,$5)`, tenant.ID, owner.DID,
		owner.SigningAlgorithm, owner.PublicKeyHex, owner.Custody); err != nil {
		return err
	}
	return tx.Commit(context.Background())
}

func (s *PostgresStore) CreateTenant(tenant Tenant) error {
	if tenant.AdministratorCount == 0 {
		tenant.AdministratorCount = tenant.Threshold
	}
	if tenant.ID == "" || tenant.OrganizationDID == "" || tenant.ServiceSlug == "" || tenant.Threshold < 1 {
		return ErrDelegationInvalid
	}
	command, err := s.pool.Exec(context.Background(), `
		INSERT INTO issuer_tenants
			(id, organization_did, service_slug, status, approval_threshold, administrator_count, policy_version, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`, tenant.ID, tenant.OrganizationDID, tenant.ServiceSlug,
		tenant.Status, tenant.Threshold, tenant.AdministratorCount, tenant.PolicyVersion, tenant.CreatedAt)
	if err != nil {
		return err
	}
	if command.RowsAffected() != 1 {
		return ErrDelegationInvalid
	}
	return nil
}

func (s *PostgresStore) Tenant(tenantID string) (Tenant, error) {
	var tenant Tenant
	err := s.pool.QueryRow(context.Background(), `
		SELECT id, organization_did, service_slug, status, approval_threshold, administrator_count, policy_version, created_at
		FROM issuer_tenants WHERE id=$1`, tenantID).Scan(
		&tenant.ID, &tenant.OrganizationDID, &tenant.ServiceSlug, &tenant.Status,
		&tenant.Threshold, &tenant.AdministratorCount, &tenant.PolicyVersion, &tenant.CreatedAt,
	)
	return tenant, mapNotFound(err)
}

func (s *PostgresStore) PutAdministrator(tenantID string, admin Administrator) error {
	if admin.TenantID != "" && admin.TenantID != tenantID {
		return ErrTenantScope
	}
	tx, err := s.pool.Begin(context.Background())
	if err != nil {
		return err
	}
	defer tx.Rollback(context.Background()) //nolint:errcheck
	var capacity, count int
	if err = tx.QueryRow(context.Background(), `
		SELECT administrator_count,
			(SELECT count(*) FROM issuer_administrators WHERE tenant_id=$1)
		FROM issuer_tenants WHERE id=$1 FOR UPDATE`, tenantID).Scan(&capacity, &count); err != nil {
		return mapNotFound(err)
	}
	var exists bool
	if err = tx.QueryRow(context.Background(), `
		SELECT EXISTS(SELECT 1 FROM issuer_administrators WHERE tenant_id=$1 AND admin_did=$2)`,
		tenantID, admin.DID).Scan(&exists); err != nil {
		return err
	}
	if !exists && count >= capacity {
		return ErrThresholdNotMet
	}
	_, err = tx.Exec(context.Background(), `
		INSERT INTO issuer_administrators
			(tenant_id, admin_did, role, state, signing_algorithm, public_key_hex, custody)
		VALUES ($1,$2,$3,$4,$5,$6,$7)
		ON CONFLICT (tenant_id, admin_did) DO UPDATE SET
			role=EXCLUDED.role, state=EXCLUDED.state,
			signing_algorithm=EXCLUDED.signing_algorithm,
			public_key_hex=EXCLUDED.public_key_hex, custody=EXCLUDED.custody`,
		tenantID, admin.DID, admin.Role, admin.State, admin.SigningAlgorithm, admin.PublicKeyHex, admin.Custody)
	if err != nil {
		return err
	}
	return tx.Commit(context.Background())
}

func (s *PostgresStore) Administrators(tenantID string) ([]Administrator, error) {
	rows, err := s.pool.Query(context.Background(), `
		SELECT tenant_id, admin_did, role, state, COALESCE(signing_algorithm,''),
			COALESCE(public_key_hex,''), COALESCE(custody,'')
		FROM issuer_administrators WHERE tenant_id=$1 ORDER BY admin_did`, tenantID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []Administrator
	for rows.Next() {
		var admin Administrator
		if err := rows.Scan(&admin.TenantID, &admin.DID, &admin.Role, &admin.State, &admin.SigningAlgorithm, &admin.PublicKeyHex, &admin.Custody); err != nil {
			return nil, err
		}
		result = append(result, admin)
	}
	return result, rows.Err()
}

func (s *PostgresStore) PutSigningKey(tenantID string, key SigningKey) error {
	if key.TenantID != "" && key.TenantID != tenantID {
		return ErrTenantScope
	}
	_, err := s.pool.Exec(context.Background(), `
		INSERT INTO issuer_signing_keys
			(id, tenant_id, kms_key_version, public_key, algorithm, protection_level, state, version, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`, key.ID, tenantID, key.KMSKeyVersion,
		[]byte(key.PublicKeyPEM), key.Algorithm, key.ProtectionLevel, key.State, key.Version, key.CreatedAt)
	return err
}

func (s *PostgresStore) SigningKey(tenantID, keyID string) (SigningKey, error) {
	var key SigningKey
	var publicKey []byte
	err := s.pool.QueryRow(context.Background(), `
		SELECT id, tenant_id, kms_key_version, public_key, algorithm, protection_level, state, version, created_at
		FROM issuer_signing_keys WHERE tenant_id=$1 AND id=$2`, tenantID, keyID).Scan(
		&key.ID, &key.TenantID, &key.KMSKeyVersion, &publicKey, &key.Algorithm,
		&key.ProtectionLevel, &key.State, &key.Version, &key.CreatedAt)
	key.PublicKeyPEM = string(publicKey)
	return key, mapNotFound(err)
}

func (s *PostgresStore) ReserveStatusIndex(tenantID string) (int64, error) {
	for attempt := 0; attempt < 256; attempt++ {
		value, err := rand.Int(rand.Reader, big.NewInt(131072))
		if err != nil {
			return 0, err
		}
		index := value.Int64()
		command, err := s.pool.Exec(context.Background(), `
			INSERT INTO issuer_status_index_reservations (tenant_id, status_index)
			VALUES ($1,$2) ON CONFLICT DO NOTHING`, tenantID, index)
		if err != nil {
			return 0, err
		}
		if command.RowsAffected() == 1 {
			return index, nil
		}
	}
	return 0, errors.New("status list index allocation collision limit")
}

func (s *PostgresStore) PutCredentialRecord(tenantID string, record CredentialRecord) error {
	if record.TenantID != "" && record.TenantID != tenantID {
		return ErrTenantScope
	}
	command, err := s.pool.Exec(context.Background(), `
		INSERT INTO credential_records
			(credential_id, tenant_id, credential_hash, credential_type, subject_pairwise_hash,
			 issued_at, expires_at, status_index, status, policy_snapshot_hash)
		SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10
		WHERE EXISTS (SELECT 1 FROM issuer_status_index_reservations WHERE tenant_id=$2 AND status_index=$8)
		ON CONFLICT (credential_id) DO NOTHING`,
		record.CredentialID, tenantID, record.CredentialHash, record.CredentialType,
		record.SubjectPairwiseHash, record.IssuedAt, record.ExpiresAt, record.StatusIndex,
		record.Status, record.PolicySnapshotHash)
	if err != nil {
		return err
	}
	if command.RowsAffected() != 1 {
		var hash string
		if err := s.pool.QueryRow(context.Background(), `SELECT credential_hash FROM credential_records WHERE tenant_id=$1 AND credential_id=$2`, tenantID, record.CredentialID).Scan(&hash); err != nil || hash != record.CredentialHash {
			return ErrDelegationInvalid
		}
	}
	return nil
}

func (s *PostgresStore) SetCredentialStatus(tenantID, credentialID, status string) error {
	if status != "active" && status != "revoked" && status != "suspended" {
		return ErrDelegationInvalid
	}
	command, err := s.pool.Exec(context.Background(), `
		UPDATE credential_records SET status=$3 WHERE tenant_id=$1 AND credential_id=$2`, tenantID, credentialID, status)
	if err != nil {
		return err
	}
	if command.RowsAffected() != 1 {
		return ErrNotFound
	}
	return nil
}

func (s *PostgresStore) CredentialRecords(tenantID string) ([]CredentialRecord, error) {
	rows, err := s.pool.Query(context.Background(), `
		SELECT credential_id, tenant_id, credential_hash, credential_type, subject_pairwise_hash,
			issued_at, expires_at, status_index, status, policy_snapshot_hash
		FROM credential_records WHERE tenant_id=$1 ORDER BY status_index`, tenantID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []CredentialRecord
	for rows.Next() {
		var record CredentialRecord
		if err := rows.Scan(&record.CredentialID, &record.TenantID, &record.CredentialHash,
			&record.CredentialType, &record.SubjectPairwiseHash, &record.IssuedAt, &record.ExpiresAt,
			&record.StatusIndex, &record.Status, &record.PolicySnapshotHash); err != nil {
			return nil, err
		}
		result = append(result, record)
	}
	return result, rows.Err()
}

func (s *PostgresStore) PutCredentialTemplate(tenantID string, template CredentialTemplate) error {
	if template.TenantID != "" && template.TenantID != tenantID {
		return ErrTenantScope
	}
	tx, err := s.pool.Begin(context.Background())
	if err != nil {
		return err
	}
	defer tx.Rollback(context.Background()) //nolint:errcheck
	if template.Active {
		if _, err = tx.Exec(context.Background(), `
			UPDATE credential_templates SET active=false WHERE tenant_id=$1 AND id=$2`,
			tenantID, template.ID); err != nil {
			return err
		}
	}
	_, err = tx.Exec(context.Background(), `
		INSERT INTO credential_templates
			(id, tenant_id, version, credential_type, claim_allowlist,
			 approval_threshold, max_ttl_days, policy, active)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`, template.ID, tenantID, template.Version,
		template.CredentialType, template.ClaimAllowlist, template.ApprovalThreshold,
		template.MaxTTLDays, map[string]any{"version": template.Version}, template.Active)
	if err != nil {
		if isUniqueViolation(err) {
			return ErrDelegationReplay
		}
		return err
	}
	return tx.Commit(context.Background())
}

func (s *PostgresStore) ActiveCredentialTemplate(tenantID, templateID string) (CredentialTemplate, error) {
	var template CredentialTemplate
	err := s.pool.QueryRow(context.Background(), `
		SELECT id, tenant_id, version, credential_type, claim_allowlist,
			approval_threshold, max_ttl_days, active
		FROM credential_templates WHERE tenant_id=$1 AND id=$2 AND active=true
		ORDER BY version DESC LIMIT 1`, tenantID, templateID).Scan(
		&template.ID, &template.TenantID, &template.Version, &template.CredentialType,
		&template.ClaimAllowlist, &template.ApprovalThreshold, &template.MaxTTLDays, &template.Active)
	return template, mapNotFound(err)
}

func (s *PostgresStore) PutIssuanceRequest(tenantID string, request IssuanceRequest) error {
	if request.TenantID != "" && request.TenantID != tenantID {
		return ErrTenantScope
	}
	_, err := s.pool.Exec(context.Background(), `
		INSERT INTO issuance_requests
			(id, tenant_id, template_id, template_version, applicant_pairwise_did,
			 applicant_hash, payload_hash, state, policy_snapshot, expires_at, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,'pending',$8,$9,$10)`, request.ID, tenantID,
		request.TemplateID, request.TemplateVersion, request.ApplicantPairwiseDID,
		request.ApplicantHash, request.PayloadHash, request.PolicySnapshot,
		request.ExpiresAt, request.CreatedAt)
	if err != nil && isUniqueViolation(err) {
		return ErrDelegationReplay
	}
	return err
}

func (s *PostgresStore) IssuanceRequest(tenantID, requestID string) (IssuanceRequest, error) {
	return scanIssuanceRequest(s.pool.QueryRow(context.Background(), `
		SELECT id, tenant_id, template_id, template_version, applicant_pairwise_did,
			applicant_hash, payload_hash, state, policy_snapshot, expires_at, created_at
		FROM issuance_requests WHERE tenant_id=$1 AND id=$2`, tenantID, requestID))
}

func (s *PostgresStore) IssuanceRequests(tenantID, state string) ([]IssuanceRequest, error) {
	rows, err := s.pool.Query(context.Background(), `
		SELECT r.id, r.tenant_id, r.template_id, r.template_version,
			r.applicant_pairwise_did, r.applicant_hash, r.payload_hash, r.state,
			r.policy_snapshot, r.expires_at, r.created_at,
			count(a.approver_did) FILTER (WHERE a.decision='approve')
		FROM issuance_requests r
		LEFT JOIN issuance_approvals a ON a.tenant_id=r.tenant_id AND a.request_id=r.id
		WHERE r.tenant_id=$1 AND ($2='' OR r.state=$2)
		GROUP BY r.id, r.tenant_id, r.template_id, r.template_version,
			r.applicant_pairwise_did, r.applicant_hash, r.payload_hash, r.state,
			r.policy_snapshot, r.expires_at, r.created_at
		ORDER BY r.created_at DESC`, tenantID, state)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []IssuanceRequest
	for rows.Next() {
		request, scanErr := scanIssuanceRequestWithApprovalCount(rows)
		if scanErr != nil {
			return nil, scanErr
		}
		result = append(result, request)
	}
	return result, rows.Err()
}

func (s *PostgresStore) DecideIssuanceRequest(tenantID string, approval IssuanceApproval, threshold int) (IssuanceRequest, error) {
	if threshold < 1 || (approval.Decision != "approve" && approval.Decision != "deny") ||
		approval.SignedIntentHash == "" {
		return IssuanceRequest{}, ErrDelegationInvalid
	}
	tx, err := s.pool.Begin(context.Background())
	if err != nil {
		return IssuanceRequest{}, err
	}
	defer tx.Rollback(context.Background()) //nolint:errcheck
	request, err := scanIssuanceRequest(tx.QueryRow(context.Background(), `
		SELECT id, tenant_id, template_id, template_version, applicant_pairwise_did,
			applicant_hash, payload_hash, state, policy_snapshot, expires_at, created_at
		FROM issuance_requests WHERE tenant_id=$1 AND id=$2 FOR UPDATE`, tenantID, approval.RequestID))
	if err != nil || request.State != "pending" {
		return IssuanceRequest{}, ErrDelegationInvalid
	}
	command, err := tx.Exec(context.Background(), `
		INSERT INTO issuance_approvals
			(tenant_id, request_id, approver_did, decision, signed_intent_hash, created_at)
		SELECT $1,$2,$3,$4,$5,$6
		WHERE EXISTS (SELECT 1 FROM issuer_administrators
			WHERE tenant_id=$1 AND admin_did=$3 AND state='active')
		ON CONFLICT (tenant_id, request_id, approver_did) DO NOTHING`, tenantID,
		approval.RequestID, approval.ApproverDID, approval.Decision,
		approval.SignedIntentHash, approval.CreatedAt)
	if err != nil || command.RowsAffected() != 1 {
		return IssuanceRequest{}, ErrDelegationInvalid
	}
	state := "pending"
	if approval.Decision == "deny" {
		state = "denied"
	} else {
		var count int
		if err = tx.QueryRow(context.Background(), `
			SELECT count(*) FROM issuance_approvals
			WHERE tenant_id=$1 AND request_id=$2 AND decision='approve'`,
			tenantID, approval.RequestID).Scan(&count); err != nil {
			return IssuanceRequest{}, err
		}
		if count >= threshold {
			state = "approved"
		}
	}
	if _, err = tx.Exec(context.Background(), `
		UPDATE issuance_requests SET state=$3 WHERE tenant_id=$1 AND id=$2`,
		tenantID, approval.RequestID, state); err != nil {
		return IssuanceRequest{}, err
	}
	request.State = state
	if err = tx.Commit(context.Background()); err != nil {
		return IssuanceRequest{}, err
	}
	return request, nil
}

func (s *PostgresStore) ConsumeApprovedIssuanceRequest(tenantID, requestID string, now time.Time) (IssuanceRequest, error) {
	return scanIssuanceRequest(s.pool.QueryRow(context.Background(), `
		UPDATE issuance_requests SET state='offered'
		WHERE tenant_id=$1 AND id=$2 AND state='approved' AND expires_at > $3
		RETURNING id, tenant_id, template_id, template_version, applicant_pairwise_did,
			applicant_hash, payload_hash, state, policy_snapshot, expires_at, created_at`,
		tenantID, requestID, now))
}

type issuanceRequestRow interface {
	Scan(dest ...any) error
}

func scanIssuanceRequest(row issuanceRequestRow) (IssuanceRequest, error) {
	var request IssuanceRequest
	var policy []byte
	err := row.Scan(&request.ID, &request.TenantID, &request.TemplateID, &request.TemplateVersion,
		&request.ApplicantPairwiseDID, &request.ApplicantHash, &request.PayloadHash,
		&request.State, &policy, &request.ExpiresAt, &request.CreatedAt)
	if err != nil {
		return IssuanceRequest{}, mapNotFound(err)
	}
	if err := json.Unmarshal(policy, &request.PolicySnapshot); err != nil {
		return IssuanceRequest{}, err
	}
	if value, ok := request.PolicySnapshot["membership_class"].(string); ok {
		request.MembershipClass = value
	}
	if value, ok := request.PolicySnapshot["board_id"].(string); ok {
		request.BoardID = value
	}
	return request, nil
}

func scanIssuanceRequestWithApprovalCount(row issuanceRequestRow) (IssuanceRequest, error) {
	var request IssuanceRequest
	var policy []byte
	err := row.Scan(&request.ID, &request.TenantID, &request.TemplateID, &request.TemplateVersion,
		&request.ApplicantPairwiseDID, &request.ApplicantHash, &request.PayloadHash,
		&request.State, &policy, &request.ExpiresAt, &request.CreatedAt, &request.ApprovalCount)
	if err != nil {
		return IssuanceRequest{}, mapNotFound(err)
	}
	if err := json.Unmarshal(policy, &request.PolicySnapshot); err != nil {
		return IssuanceRequest{}, err
	}
	if value, ok := request.PolicySnapshot["membership_class"].(string); ok {
		request.MembershipClass = value
	}
	if value, ok := request.PolicySnapshot["board_id"].(string); ok {
		request.BoardID = value
	}
	return request, nil
}

func (s *PostgresStore) ProposeDelegation(tenantID string, delegation Delegation) error {
	if delegation.TenantID != "" && delegation.TenantID != tenantID {
		return ErrTenantScope
	}
	_, err := s.pool.Exec(context.Background(), `
		INSERT INTO issuer_key_delegations
			(id, tenant_id, signing_key_id, sequence, canonical_payload, payload_hash,
			 root_signatures, credential_types, not_before, expires_at, state)
		VALUES ($1,$2,$3,$4,$5,$6,'{}'::jsonb,$7,$8,$9,'proposed')`,
		delegation.ID, tenantID, delegation.SigningKeyID, delegation.Sequence,
		delegation.CanonicalJSON, delegation.PayloadHash, delegation.CredentialTypes,
		delegation.NotBefore, delegation.ExpiresAt)
	if err != nil && isUniqueViolation(err) {
		return ErrDelegationReplay
	}
	return err
}

func (s *PostgresStore) ApproveDelegation(tenantID, delegationID, adminDID string, signature []byte) error {
	encoded := base64.RawURLEncoding.EncodeToString(signature)
	command, err := s.pool.Exec(context.Background(), `
		UPDATE issuer_key_delegations d
		SET root_signatures = d.root_signatures || jsonb_build_object($3::text, $4::text)
		WHERE d.tenant_id=$1 AND d.id=$2 AND d.state='proposed'
		  AND EXISTS (SELECT 1 FROM issuer_administrators a
		              WHERE a.tenant_id=$1 AND a.admin_did=$3 AND a.state='active')`,
		tenantID, delegationID, adminDID, encoded)
	if err != nil {
		return err
	}
	if command.RowsAffected() != 1 {
		return ErrNotFound
	}
	return nil
}

func (s *PostgresStore) ActivateDelegation(tenantID, delegationID string, now time.Time) error {
	tx, err := s.pool.Begin(context.Background())
	if err != nil {
		return err
	}
	defer tx.Rollback(context.Background()) //nolint:errcheck
	var threshold, approvals int
	err = tx.QueryRow(context.Background(), `
		SELECT t.approval_threshold, jsonb_object_length(d.root_signatures)
		FROM issuer_key_delegations d JOIN issuer_tenants t ON t.id=d.tenant_id
		WHERE d.tenant_id=$1 AND d.id=$2 AND d.state='proposed'
		  AND d.not_before <= $3 AND d.expires_at > $3
		FOR UPDATE OF d, t`, tenantID, delegationID, now).Scan(&threshold, &approvals)
	if err != nil {
		return mapNotFound(err)
	}
	if approvals < threshold {
		return ErrThresholdNotMet
	}
	if _, err = tx.Exec(context.Background(), `UPDATE issuer_key_delegations SET state='superseded' WHERE tenant_id=$1 AND state='active'`, tenantID); err != nil {
		return err
	}
	if _, err = tx.Exec(context.Background(), `UPDATE issuer_key_delegations SET state='active' WHERE tenant_id=$1 AND id=$2`, tenantID, delegationID); err != nil {
		return err
	}
	if _, err = tx.Exec(context.Background(), `UPDATE issuer_tenants SET status='active' WHERE id=$1`, tenantID); err != nil {
		return err
	}
	return tx.Commit(context.Background())
}

func (s *PostgresStore) RevokeDelegation(tenantID, delegationID string, _ time.Time) error {
	tx, err := s.pool.Begin(context.Background())
	if err != nil {
		return err
	}
	defer tx.Rollback(context.Background()) //nolint:errcheck
	var state string
	if err = tx.QueryRow(context.Background(), `
		SELECT state FROM issuer_key_delegations
		WHERE tenant_id=$1 AND id=$2 FOR UPDATE`, tenantID, delegationID).Scan(&state); err != nil {
		return mapNotFound(err)
	}
	if _, err = tx.Exec(context.Background(), `
		UPDATE issuer_key_delegations SET state='revoked'
		WHERE tenant_id=$1 AND id=$2`, tenantID, delegationID); err != nil {
		return err
	}
	if state == "active" {
		if _, err = tx.Exec(context.Background(), `
			UPDATE issuer_tenants SET status='paused' WHERE id=$1`, tenantID); err != nil {
			return err
		}
	}
	return tx.Commit(context.Background())
}

func (s *PostgresStore) ActiveDelegation(tenantID string, now time.Time) (Delegation, error) {
	return s.delegationRow(s.pool.QueryRow(context.Background(), `
		SELECT id, tenant_id, signing_key_id, sequence, canonical_payload::text, payload_hash,
			root_signatures, credential_types, not_before, expires_at, state
		FROM issuer_key_delegations
		WHERE tenant_id=$1 AND state='active' AND not_before <= $2 AND expires_at > $2`, tenantID, now))
}

func (s *PostgresStore) delegationRow(row pgx.Row) (Delegation, error) {
	var delegation Delegation
	var canonical string
	var approvalsJSON []byte
	if err := row.Scan(&delegation.ID, &delegation.TenantID, &delegation.SigningKeyID,
		&delegation.Sequence, &canonical, &delegation.PayloadHash, &approvalsJSON,
		&delegation.CredentialTypes, &delegation.NotBefore, &delegation.ExpiresAt, &delegation.State); err != nil {
		return Delegation{}, mapNotFound(err)
	}
	delegation.CanonicalJSON = []byte(canonical)
	var encoded map[string]string
	if err := json.Unmarshal(approvalsJSON, &encoded); err != nil {
		return Delegation{}, err
	}
	delegation.Approvals = make(map[string][]byte, len(encoded))
	for did, value := range encoded {
		signature, err := base64.RawURLEncoding.DecodeString(value)
		if err != nil {
			return Delegation{}, err
		}
		delegation.Approvals[did] = signature
	}
	return delegation, nil
}

func (s *PostgresStore) AppendAudit(tenantID string, event AuditEvent) error {
	if event.TenantID != "" && event.TenantID != tenantID {
		return ErrTenantScope
	}
	_, err := s.pool.Exec(context.Background(), `
		INSERT INTO issuer_audit_events
			(id, tenant_id, event_type, actor_did, request_hash, policy_version, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7)`, event.ID, tenantID, event.EventType,
		event.ActorDID, event.RequestHash, event.PolicyVersion, event.CreatedAt)
	return err
}

func (s *PostgresStore) Audit(tenantID string) ([]AuditEvent, error) {
	rows, err := s.pool.Query(context.Background(), `
		SELECT id, tenant_id, event_type, COALESCE(actor_did,''), request_hash, policy_version, created_at
		FROM issuer_audit_events WHERE tenant_id=$1 ORDER BY created_at, id`, tenantID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []AuditEvent
	for rows.Next() {
		var event AuditEvent
		if err := rows.Scan(&event.ID, &event.TenantID, &event.EventType, &event.ActorDID, &event.RequestHash, &event.PolicyVersion, &event.CreatedAt); err != nil {
			return nil, err
		}
		result = append(result, event)
	}
	return result, rows.Err()
}

func (s *PostgresStore) PutAdminCapability(capability AdminCapability) error {
	_, err := s.pool.Exec(context.Background(), `
		INSERT INTO issuer_admin_capabilities
			(token_hash, tenant_id, admin_did, scopes, audience, expires_at, revoked_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7)`, capability.TokenHash, capability.TenantID,
		capability.AdminDID, capability.Scopes, capability.Audience, capability.ExpiresAt,
		capability.RevokedAt)
	return err
}

func (s *PostgresStore) AdminCapabilityByHash(hash string) (AdminCapability, error) {
	var capability AdminCapability
	err := s.pool.QueryRow(context.Background(), `
		SELECT token_hash, tenant_id, admin_did, scopes, audience, expires_at, revoked_at
		FROM issuer_admin_capabilities WHERE token_hash=$1`, hash).Scan(
		&capability.TokenHash, &capability.TenantID, &capability.AdminDID,
		&capability.Scopes, &capability.Audience, &capability.ExpiresAt, &capability.RevokedAt,
	)
	return capability, mapNotFound(err)
}

func (s *PostgresStore) RevokeAdminCapabilities(tenantID, adminDID string, at time.Time) error {
	_, err := s.pool.Exec(context.Background(), `
		UPDATE issuer_admin_capabilities SET revoked_at=$3
		WHERE tenant_id=$1 AND admin_did=$2 AND revoked_at IS NULL`, tenantID, adminDID, at)
	return err
}

func (s *PostgresStore) AdminWebAuthnCredentials(tenantID, adminDID string) ([]webauthn.Credential, error) {
	rows, err := s.pool.Query(context.Background(), `
		SELECT credential_json FROM issuer_admin_credentials
		WHERE tenant_id=$1 AND admin_did=$2 ORDER BY created_at`, tenantID, adminDID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []webauthn.Credential
	for rows.Next() {
		var encoded []byte
		if err := rows.Scan(&encoded); err != nil {
			return nil, err
		}
		var credential webauthn.Credential
		if err := json.Unmarshal(encoded, &credential); err != nil {
			return nil, err
		}
		result = append(result, credential)
	}
	return result, rows.Err()
}

func (s *PostgresStore) PutAdminWebAuthnCredential(tenantID, adminDID string, credential webauthn.Credential) error {
	encoded, err := json.Marshal(credential)
	if err != nil {
		return err
	}
	transports := make([]string, len(credential.Transport))
	for i, transport := range credential.Transport {
		transports[i] = string(transport)
	}
	_, err = s.pool.Exec(context.Background(), `
		INSERT INTO issuer_admin_credentials
			(tenant_id, admin_did, credential_id, cose_public_key, sign_count, transports, credential_json)
		VALUES ($1,$2,$3,$4,$5,$6,$7)`, tenantID, adminDID, credential.ID,
		credential.PublicKey, credential.Authenticator.SignCount, transports, encoded)
	return err
}

func (s *PostgresStore) UpdateAdminWebAuthnCredential(tenantID, adminDID string, credential webauthn.Credential) error {
	encoded, err := json.Marshal(credential)
	if err != nil {
		return err
	}
	command, err := s.pool.Exec(context.Background(), `
		UPDATE issuer_admin_credentials SET sign_count=$4, credential_json=$5
		WHERE tenant_id=$1 AND admin_did=$2 AND credential_id=$3`, tenantID, adminDID,
		credential.ID, credential.Authenticator.SignCount, encoded)
	if err != nil {
		return err
	}
	if command.RowsAffected() != 1 {
		return ErrNotFound
	}
	return nil
}

func (s *PostgresStore) PutAdminWebAuthnSession(session AdminWebAuthnSession) error {
	encoded, err := json.Marshal(session.Data)
	if err != nil {
		return err
	}
	challengeHash := sha256.Sum256([]byte(session.Data.Challenge))
	_, err = s.pool.Exec(context.Background(), `
		INSERT INTO issuer_admin_challenges
			(id, tenant_id, admin_did, purpose, challenge_hash, origin, rp_id, expires_at, session_data, scopes)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`, session.ID, session.TenantID, session.AdminDID,
		session.Purpose, hex.EncodeToString(challengeHash[:]), session.Origin, session.RPID,
		session.ExpiresAt, encoded, session.Scopes)
	return err
}

func (s *PostgresStore) TakeAdminWebAuthnSession(id, tenantID, adminDID, purpose string, now time.Time) (AdminWebAuthnSession, error) {
	tx, err := s.pool.Begin(context.Background())
	if err != nil {
		return AdminWebAuthnSession{}, err
	}
	defer tx.Rollback(context.Background()) //nolint:errcheck
	var session AdminWebAuthnSession
	var encoded []byte
	err = tx.QueryRow(context.Background(), `
		SELECT id, tenant_id, admin_did, purpose, origin, rp_id, expires_at, session_data, scopes
		FROM issuer_admin_challenges
		WHERE id=$1 AND tenant_id=$2 AND admin_did=$3 AND purpose=$4
		  AND consumed_at IS NULL AND expires_at > $5 FOR UPDATE`,
		id, tenantID, adminDID, purpose, now).Scan(&session.ID, &session.TenantID, &session.AdminDID,
		&session.Purpose, &session.Origin, &session.RPID, &session.ExpiresAt, &encoded, &session.Scopes)
	if err != nil {
		return AdminWebAuthnSession{}, mapNotFound(err)
	}
	if err := json.Unmarshal(encoded, &session.Data); err != nil {
		return AdminWebAuthnSession{}, err
	}
	if _, err := tx.Exec(context.Background(), `UPDATE issuer_admin_challenges SET consumed_at=$2 WHERE id=$1`, id, now); err != nil {
		return AdminWebAuthnSession{}, err
	}
	if err := tx.Commit(context.Background()); err != nil {
		return AdminWebAuthnSession{}, err
	}
	session.Consumed = true
	return session, nil
}

func mapNotFound(err error) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	return err
}

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

var _ Store = (*PostgresStore)(nil)
var _ AdminCapabilityStore = (*PostgresStore)(nil)
var _ AdminWebAuthnStore = (*PostgresStore)(nil)
