[

# PID
(.subject.reference | split("/") | nth(1)) // null

# OID
, (.id) // null

# DIA
, first(.component[]?
  | select(.code.coding[]? | [.system, .code] == ["http://loinc.org", "8462-4"])
  | .valueQuantity.value
) // null

# SYS
, first(.component[]?
  | select(.code.coding[]? | [.system, .code] == ["http://loinc.org", "8480-6"])
  | .valueQuantity.value
) // null

# DATE
, (.effectiveDateTime) // null

]
| @csv
