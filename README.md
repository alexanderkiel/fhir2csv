# Extract Tabular Data from FHIR Resources

## Background

FHIR resources represent medical data in hierarchical form. However data scientists work with tabular data. Currently a number of projects try to solve this impedance mismatch. One of this is [Fhir2Tables][1] from Thomas Peschel.

## Other Approaches

Fhir2Tables uses the R package [fhirR][2]. This package provides functionality to issue FHIR search requests to a FHIR server and convert the resulting bundles into R data frames. The conversion is done by specifying XPath expressions for each column of the data frame.

IMHO this is a very good fit for data scientists which work directly in R. However in other scenarios, e.g. automated ETL processes, it might be an overhead to maintain a working R installation which will process the conversation correctly. Another limitation of fhirR is that it needs the resources in XML format because it uses XPath.

## My Proposal

While exploring solutions which don't require an R installation and work with JSON, I came up with the command line tool [jq][3] which is available on all platforms and well established in the world of JSON. With jq the extraction of specific values from FHIR resources is possible. Even a direct CSV output is provided.

The jq filters, I like to show here, convert one FHIR resource into one line of CSV data. If you clone this repository, you can run the following, assuming you have jq installed:

```sh
cat blood-pressure-observation.json | jq -f blood-pressure.jq
```

The output should be:

```
"402","409",12,11,"2019-09-18T15:20:28+03:00"
```

In addition to a single resource, the same filter can also be used to process a stream of resources which generates a stream of CSV data lines. One possibility to generate a stream of resources is to apply another jq filter to a bundle of resources. If you run the following:

```sh
cat blood-pressure-bundle.json | jq '.entry[]? | .resource' | jq -rf blood-pressure.jq
```

The output should be:

```
"402","409",12,11,"2019-09-18T15:20:28+03:00"
"402","408",12,11,"2019-09-18T15:20:28+03:00"
"402","405",12,11,"2019-09-18T15:20:28+03:00"
"402","406",12,11,"2019-09-18T15:20:28+03:00"
"402","407",12,11,"2019-09-18T15:20:28+03:00"
"402","417",,,"2019-09-18T15:20:28+03:00"
"402","411",12,11,"2019-09-18T15:20:28+03:00"
"402","412",12,11,"2019-09-18T15:20:28+03:00"
"1233","1245",80,120,"2019-09-19T14:26:26-04:00"
"402","1193",11,12,"2019-09-19T17:17:57+03:00"
```

Streams of resources can be also obtained from [FHIR Bulk Data Access][4] which should make jq a good fit to process large FHIR data exports into CSV files.

## JQ Filters in Detail

In our blood pressure example the the jq filter file is the following:

```
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
```

Here the basic shape is:

```
[ <column-filter-0>, ..., <column-filter-n> ] | @csv
```

where `[]` is an [array construction][5] for the CSV row and the `@csv` [syntax][6] actually outputs that array in CSV format. The [pipe][7] `|` operator combines that two filters. Within the array a separate filter for each column is used. 

The most simple filter used for the OID (object identifier) is:

```
(.id) // null
```

where we select the Observation id property using the [object identifier filter][8] `.id`. We have to put that filter inside parentheses in order to allow the next filter to access the resources root again. The [alternative operator][9] (`//`) followed by `null` is used to ensure that the column isn't omitted if there is no id property in the resource. You will find the pattern `(<real-filter>) // null` in all column filters so I will not repeat it.

The next more advanced filter used for the PID (patient identifier) is:

```
.subject.reference | split("/") | nth(1)
```

Here the object identifier filter `.subject.reference` is used to select the reference property inside the subject complex type. After that [split][10] is used to separate the subject type `Patient` from its identifier and [nth][11] is used to output the second part of the split, the identifier.

The last example of an filter used for DIA (diastolic blood pressure) is:

```
.component[]?
  | select(.code.coding[]? | [.system, .code] == ["http://loinc.org", "8462-4"])
  | .valueQuantity.value
```

Here we first descent into the component complex type with can have multiple values. That's the reason we use [array/object value iterator][12] (`.component[]?`) which will output each value individually and doesn't error on missing component complex type. After that we continue with the [select function][13] with will select the Observation component based on the following FHIR structure:

```json
{
  "code": {
    "coding": [
      {
        "system": "http://loinc.org",
        "code": "8462-4",
        "display": "Diastolic blood pressure"
      }
    ]
  }
}
```

Here `.code.coding[]?` descents into the Coding followed by `[.system, .code`] which extract the system and code into an array. The array is than compared to the `["http://loinc.org", "8462-4"]` array.

After the appropriate Observation component is selected, the filter `.valueQuantity.value` extracts its quantity value.

## Conclusion

I have show that it's possible to extract tabular data in CSV format from a stream of FHIR resources of one type using the widely available command line tool jq. Streams of FHIR resources can be generated from FHIR bundles using jq itself or be obtained by FHIR Bulk Data Access.

A one-shot FHIR search to CSV solution is currently not possible with my solution because FHIR search uses paging with one FHIR bundle per page. An additional tool would be necessary with follows the page links obtaining bundle after bundle and outputting a stream of FHIR resources. It's possible to build such functionality into [blazectl][14]. With that a one-shot solution export of resources of a single type directly into a CSV file would look like this:

```sh
blazectl --server https://hapi.fhir.org/baseR4 search --type Observation --query 'code=http://loinc.org|85354-9' | jq -rf blood-pressure.jq > blood-pressure.csv
```

[1]: <https://gitlab.com/TPeschel/fhir2tables>
[2]: <https://tpeschel.github.io/fhiR/>
[3]: <https://stedolan.github.io/jq/>
[4]: <https://hl7.org/fhir/uv/bulkdata/>
[5]: <https://stedolan.github.io/jq/manual/#TypesandValues>
[6]: <https://stedolan.github.io/jq/manual/#Formatstringsandescaping>
[7]: <https://stedolan.github.io/jq/manual/#Pipe:|>
[8]: <https://stedolan.github.io/jq/manual/#Basicfilters>
[9]: <https://stedolan.github.io/jq/manual/#ConditionalsandComparisons>
[10]: <https://stedolan.github.io/jq/manual/#split(str)>
[11]: <https://stedolan.github.io/jq/manual/#first,last,nth(n)>
[12]: <https://stedolan.github.io/jq/manual/#Array/ObjectValueIterator:.[]>
[13]: <https://stedolan.github.io/jq/manual/#select(boolean_expression)>
[14]: <https://github.com/samply/blazectl>
