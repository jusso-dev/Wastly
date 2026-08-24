# Offline food data

Wastly bundles 4,128 unique Australian food profiles from every food row in:

- [AUSNUT 2023 food nutrient profiles](https://www.foodstandards.gov.au/science-data/food-nutrient-databases/ausnut/data-files): 3,741 foods.
- [Australian Food Composition Database Release 3 nutrient profiles](https://www.foodstandards.gov.au/science-data/food-nutrient-databases/afcd/data-files): 1,588 foods, including 387 public food keys absent from AUSNUT 2023.

The generated catalogue keeps each public food key, food name, and energy with dietary fibre in kJ per 100 g. AUSNUT 2023 wins where the same public food key occurs in both datasets. Wastly also retains eight legacy seed entries for barcode compatibility, making 4,136 bundled search rows. This is complete for the two named FSANZ datasets; it is not a claim to contain every branded retail product sold worldwide.

## Licence and attribution

Food composition data is provided by Food Standards Australia New Zealand (FSANZ) under the [FSANZ Data User Licence Agreement](https://www.foodstandards.gov.au/science-data/monitoringnutrients/afcd/datauserlicenceagreement), which is based on Creative Commons Attribution-ShareAlike 3.0 Australia. The derived `seed-foods.json` data is distributed under that agreement. Combining the data resource with Wastly does not apply the data licence to unrelated application code.

Changes made: the two files were combined by public food key; overlapping rows prefer AUSNUT 2023; all nutrient columns except energy with dietary fibre were removed; identifiers were namespaced with `fsanz:`; rows were sorted by food name; and the result was encoded as JSON.

There are limitations associated with food composition databases. Food composition data used in the database or databases may represent an average of the nutrient content of a particular sample of foods and ingredients, determined at a particular time. The nutrient composition of foods and ingredients can vary substantially between batches and brands because of a number of factors, including changes in season, processing practices and ingredient source, and methods of calculation.

This work is based on Australian data. Australian data may not be appropriate for use in other countries.

## Rebuild

Download the two nutrient-profile workbooks linked above, then run:

```sh
python3 Scripts/generate_offline_food_catalog.py \
  /path/to/AUSNUT-2023-Food-nutrient-profiles.xlsx \
  /path/to/AFCD-Release-3-Nutrient-profiles.xlsx \
  Sources/WastlyKit/Resources/seed-foods.json
```

The generator uses only Python's standard library and rejects unexpected source files or row counts. Accepted source SHA-256 values:

- AUSNUT 2023: `374650afc59951009d5ddf48fe35f712467458eb07eef513ea9f54c8f110f317`
- AFCD Release 3: `14cb3e73dbf58987b440e6299624c0fefd7a4e61591fc1f753995d9534e0efc9`
