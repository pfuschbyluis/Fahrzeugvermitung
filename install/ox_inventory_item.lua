-- In ox_inventory/data/items.lua einfügen.
-- Danach ox_inventory UND MB_Fahrzeugvermitung neu starten.
-- Wichtig: item name muss exakt 'mietvertrag' sein.

['mietvertrag'] = {
    label = 'Mietvertrag',
    weight = 1,
    stack = false,
    close = true,
    consume = 0,
    description = 'Ein unterschriebener Mietvertrag',
    client = {
        event = 'MB_Fahrzeugvermitung:client:useContractItem'
    }
},
