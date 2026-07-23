# Trusted ePassport CSCA anchors

`taiwan.pem` contains current, unexpired Taiwan ePassport CSCA public
certificates published by the Bureau of Consular Affairs, Ministry of Foreign
Affairs.

- Source: https://www.boca.gov.tw/cp-243-4449-23912-2.html
- `CSCA20240321.der` SHA-256:
  `A5:5C:44:72:BC:A8:5A:F3:42:2C:E3:BD:57:3C:30:74:A8:34:ED:B2:1A:E5:C7:EF:76:F9:9E:C6:A0:52:D3:CF`
- `CSCA20201127.der` SHA-256:
  `C6:34:66:EF:6B:7A:1D:C3:BD:EB:CA:83:7E:22:EC:1C:44:9D:14:E4:E1:5B:25:5C:90:F9:33:41:B6:FF:E9:DE`
- Retrieved: 2026-07-23

This trust store intentionally supports only documents chaining to the listed
Taiwan CSCA. Unknown issuing-country chains fail closed and must not produce a
verified-human credential. Adding another country requires an authenticated
government or ICAO source, fingerprint review, expiry/revocation handling, and
a Constitution Review.
