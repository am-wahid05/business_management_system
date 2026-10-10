# Weekly Purchasing Intelligence integration

The initial Python module is standalone and uses only the Python standard
library. It accepts UTF-8 JSON on standard input and writes one JSON result to
standard output:

```json
{
  "schema_version": 1,
  "weeks": [
    {
      "week_start": "2026-09-28",
      "products": {
        "cashew": 1200.5,
        "cocoa": 850
      }
    }
  ]
}
```

`week_start` is an ISO date for Monday. `products` maps product IDs to
non-negative weekly aggregate weights in kilograms. Missing product entries
and null weights mean zero. The snapshot must be constructed in Dart from the
active company's existing scoped analytics/data layer; do not include supplier
names, delivery rows, credentials, or another company's values.

The module reports weekly totals and latest-week product values, week-over-week
percentage changes, historical means and medians, and an advisory unusual
volume signal. It requires four prior weeks and signals only when the latest
value is greater than the historical mean plus two population standard
deviations. A zero previous-week baseline produces no percentage for a positive
current value. The method is descriptive, not a forecast or an automatic
business action.

## Local development configuration

The app reads the optional compile-time values
`WEEKLY_PURCHASING_PYTHON_EXECUTABLE` and
`WEEKLY_PURCHASING_PYTHON_SCRIPT` from Dart defines. Set them when invoking
`flutter run` or building locally; keep machine-specific paths out of source
control. If either is missing, the Analytics screen explains that Python is
not configured and normal Dart analytics continue to work. The service passes
the script as a separate process argument and sends only the aggregate JSON
snapshot over standard input.

For a local Windows development run, supply the paths in the launch command:

```powershell
flutter run -d windows `
  --dart-define="WEEKLY_PURCHASING_PYTHON_EXECUTABLE=<installed-python-executable>" `
  --dart-define="WEEKLY_PURCHASING_PYTHON_SCRIPT=<workspace>\python\weekly_purchasing_intelligence.py"
```

The real-process service test uses synthetic in-memory company data. Set
`WEEKLY_PURCHASING_TEST_PYTHON` to the Python executable and optionally set
`WEEKLY_PURCHASING_TEST_PYTHON_SCRIPT` to the script path when running
`weekly_purchasing_intelligence_service_test.dart`. Point both values to the
Release bundle to verify its runtime and script without using installed Python.

## Windows runtime bundle

The Windows CMake install bundle stages Python under `python\` beside the
application executable. The app resolves `python\python.exe` and
`python\weekly_purchasing_intelligence.py` relative to
`Platform.resolvedExecutable`; development Dart defines still override those
paths when explicitly supplied. The Windows build fails configuration if the
verified runtime stage is missing.

Pinned runtime: CPython 3.13.15 x64 embeddable distribution from
`https://www.python.org/ftp/python/3.13.15/python-3.13.15-embeddable-amd64.zip`.
Its expected SHA-256 is
`791ada5e20aba24524f8d939cdeb069976d632a699fe5cb65274b23f4545e68a`, copied
from the official `windows-3.13.15.json` release metadata. The Python directory
index listed 11,009,825 bytes, but the independently downloaded archive whose
hash matches the official metadata is 11,010,501 bytes; release metadata does
not publish a size. The preparation script treats the official SHA-256 as
authoritative and refuses to extract on mismatch.

Run `powershell -ExecutionPolicy Bypass -File
tooling\prepare_weekly_python_runtime.ps1` before `flutter build windows`. The
script downloads only to a temporary location, verifies SHA-256, and stages
runtime files under ignored `build\windows\weekly_python_runtime`; it never
commits the binary runtime. `LICENSE.txt` from the official runtime is copied
into the bundle to carry the Python Software Foundation license and included
third-party notices. Review it as part of release distribution.

After building, run
`powershell -ExecutionPolicy Bypass -File
tooling\verify_weekly_python_bundle.ps1 -BundleDirectory
build\windows\x64\runner\Release`. The check verifies required runtime/script/
license files and invokes the bundled interpreter with synthetic JSON input.
The existing SQLite/Dart analytics remain available if the runtime files are
missing or Python execution fails.

The repository has no separate installer project. This change integrates and
verifies the existing CMake install bundle; installer creation and installer-
level launch testing remain separate distribution work.
