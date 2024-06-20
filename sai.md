
# Required Parameters


|paramterName|description|parameterType|
|---|---|---|

# Optional Parameters


|paramterName|description|parameterType|
|---|---|---|
|templateSpecName||string|
|templateSpecVersion||string|
|location||string|

# Resource Parameters


|resourceName|resourceType|resourceVersion|
|---|---|---|
|templateSpecName_resource|'Microsoft.Resources/templateSpecs@2019-06-01-preview'|2019-06-01-preview|
|templateSpecName_templateSpecVersion|'Microsoft.Resources/templateSpecs/versions@2019-06-01-preview'|2019-06-01-preview|

# Conditional Parameters


|paramterName|description|parameterType|allowedValues|
|---|---|---|---|
|storageSKU|('Optional. The storage SKU associated with the deployment')|string|'Standard_LRS','Standard_GRS','Standard_RAGRS','Standard_ZRS','Premium_LRS','Premium_ZRS','Standard_GZRS','Standard_RAGZRS',|
