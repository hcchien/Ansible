package vc

import (
	"bytes"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"math/big"
	"sort"
	"strconv"
	"strings"
)

const (
	dataIntegrityProofType = "DataIntegrityProof"
	eddsaJCS2022           = "eddsa-jcs-2022"
	base58BTCAlphabet      = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
)

func dataIntegrityHashData(document, proofConfig any) ([]byte, error) {
	transformedDocument, err := canonicalizeJSON(document)
	if err != nil {
		return nil, fmt.Errorf("canonicalize document: %w", err)
	}
	canonicalProofConfig, err := canonicalizeJSON(proofConfig)
	if err != nil {
		return nil, fmt.Errorf("canonicalize proof config: %w", err)
	}

	proofConfigHash := sha256.Sum256(canonicalProofConfig)
	transformedDocumentHash := sha256.Sum256(transformedDocument)
	hashData := make([]byte, 0, sha256.Size*2)
	hashData = append(hashData, proofConfigHash[:]...)
	hashData = append(hashData, transformedDocumentHash[:]...)
	return hashData, nil
}

func canonicalizeJSON(value any) ([]byte, error) {
	normalized, err := normalizeJSON(value)
	if err != nil {
		return nil, err
	}
	var buf bytes.Buffer
	if err := writeCanonicalJSON(&buf, normalized); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func normalizeJSON(value any) (any, error) {
	b, err := json.Marshal(value)
	if err != nil {
		return nil, err
	}
	decoder := json.NewDecoder(bytes.NewReader(b))
	decoder.UseNumber()
	var normalized any
	if err := decoder.Decode(&normalized); err != nil {
		return nil, err
	}
	return normalized, nil
}

func writeCanonicalJSON(buf *bytes.Buffer, value any) error {
	switch v := value.(type) {
	case nil:
		buf.WriteString("null")
	case bool:
		if v {
			buf.WriteString("true")
		} else {
			buf.WriteString("false")
		}
	case string:
		encoded, err := jsonString(v)
		if err != nil {
			return err
		}
		buf.WriteString(encoded)
	case json.Number:
		encoded, err := canonicalJSONNumber(v)
		if err != nil {
			return err
		}
		buf.WriteString(encoded)
	case []any:
		buf.WriteByte('[')
		for i, item := range v {
			if i > 0 {
				buf.WriteByte(',')
			}
			if err := writeCanonicalJSON(buf, item); err != nil {
				return err
			}
		}
		buf.WriteByte(']')
	case map[string]any:
		keys := make([]string, 0, len(v))
		for key := range v {
			keys = append(keys, key)
		}
		sort.Strings(keys)

		buf.WriteByte('{')
		for i, key := range keys {
			if i > 0 {
				buf.WriteByte(',')
			}
			encodedKey, err := jsonString(key)
			if err != nil {
				return err
			}
			buf.WriteString(encodedKey)
			buf.WriteByte(':')
			if err := writeCanonicalJSON(buf, v[key]); err != nil {
				return err
			}
		}
		buf.WriteByte('}')
	default:
		return fmt.Errorf("unsupported JSON value %T", value)
	}
	return nil
}

func jsonString(value string) (string, error) {
	var buf bytes.Buffer
	encoder := json.NewEncoder(&buf)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(value); err != nil {
		return "", err
	}
	return strings.TrimSuffix(buf.String(), "\n"), nil
}

func canonicalJSONNumber(number json.Number) (string, error) {
	raw := number.String()
	if i, err := strconv.ParseInt(raw, 10, 64); err == nil {
		return strconv.FormatInt(i, 10), nil
	}
	f, err := strconv.ParseFloat(raw, 64)
	if err != nil || math.IsInf(f, 0) || math.IsNaN(f) {
		return "", fmt.Errorf("invalid JSON number %q", raw)
	}
	return strconv.FormatFloat(f, 'g', -1, 64), nil
}

func proofOptionsMap(proof *Proof) (map[string]any, error) {
	b, err := json.Marshal(proof)
	if err != nil {
		return nil, err
	}
	decoder := json.NewDecoder(bytes.NewReader(b))
	decoder.UseNumber()
	var out map[string]any
	if err := decoder.Decode(&out); err != nil {
		return nil, err
	}
	delete(out, "proofValue")
	return out, nil
}

func credentialDocumentMap(cred *Credential) (map[string]any, error) {
	clone := *cred
	clone.Proof = nil

	b, err := json.Marshal(&clone)
	if err != nil {
		return nil, err
	}
	decoder := json.NewDecoder(bytes.NewReader(b))
	decoder.UseNumber()
	var out map[string]any
	if err := decoder.Decode(&out); err != nil {
		return nil, err
	}
	return out, nil
}

func copyMapWithout(source map[string]any, omittedKey string) map[string]any {
	out := make(map[string]any, len(source))
	for key, value := range source {
		if key == omittedKey {
			continue
		}
		out[key] = value
	}
	return out
}

func proofContextIsDocumentPrefix(documentContext, proofContext any) bool {
	documentItems := contextItems(documentContext)
	proofItems := contextItems(proofContext)
	if len(proofItems) == 0 || len(proofItems) > len(documentItems) {
		return false
	}
	for i, proofItem := range proofItems {
		if fmt.Sprint(documentItems[i]) != fmt.Sprint(proofItem) {
			return false
		}
	}
	return true
}

func contextItems(value any) []any {
	switch v := value.(type) {
	case string:
		return []any{v}
	case []string:
		items := make([]any, len(v))
		for i, item := range v {
			items[i] = item
		}
		return items
	case []any:
		return v
	default:
		return nil
	}
}

func multibaseBase58BTCEncode(data []byte) string {
	return "z" + base58BTCEncode(data)
}

func multibaseBase58BTCDecode(value string) ([]byte, error) {
	if !strings.HasPrefix(value, "z") {
		return nil, errors.New("proofValue must use base58-btc multibase")
	}
	return base58BTCDecode(strings.TrimPrefix(value, "z"))
}

func base58BTCEncode(data []byte) string {
	if len(data) == 0 {
		return ""
	}

	zeroes := 0
	for zeroes < len(data) && data[zeroes] == 0 {
		zeroes++
	}

	n := new(big.Int).SetBytes(data)
	base := big.NewInt(58)
	zero := big.NewInt(0)
	mod := new(big.Int)
	var encoded []byte
	for n.Cmp(zero) > 0 {
		n.DivMod(n, base, mod)
		encoded = append(encoded, base58BTCAlphabet[mod.Int64()])
	}
	for i := 0; i < zeroes; i++ {
		encoded = append(encoded, base58BTCAlphabet[0])
	}

	for i, j := 0, len(encoded)-1; i < j; i, j = i+1, j-1 {
		encoded[i], encoded[j] = encoded[j], encoded[i]
	}
	return string(encoded)
}

func base58BTCDecode(encoded string) ([]byte, error) {
	if encoded == "" {
		return nil, nil
	}

	n := big.NewInt(0)
	base := big.NewInt(58)
	for _, r := range encoded {
		index := strings.IndexRune(base58BTCAlphabet, r)
		if index < 0 {
			return nil, fmt.Errorf("invalid base58-btc character %q", r)
		}
		n.Mul(n, base)
		n.Add(n, big.NewInt(int64(index)))
	}

	decoded := n.Bytes()
	zeroes := 0
	for zeroes < len(encoded) && encoded[zeroes] == base58BTCAlphabet[0] {
		zeroes++
	}
	if zeroes > 0 {
		decoded = append(bytes.Repeat([]byte{0}, zeroes), decoded...)
	}
	return decoded, nil
}

func verifyEd25519Signature(pub ed25519.PublicKey, hashData []byte, proofBytes []byte) bool {
	if len(proofBytes) != ed25519.SignatureSize {
		return false
	}
	return ed25519.Verify(pub, hashData, proofBytes)
}
