module OandaApiV20Backtest
  INITIAL_BALANCE = 10_000.00

  LEVERAGE = 0.01 # Leverage of 100:1 = 0.01, 50:1 = 0.02, 10:1 = 0.1 & 1:1 = 1

  CANDLESTICK_GRANULARITY = {
    5         => 'S5',
    10        => 'S10',
    15        => 'S15',
    30        => 'S30',
    60        => 'M1',
    120       => 'M2',
    180       => 'M3',
    240       => 'M4',
    300       => 'M5',
    600       => 'M10',
    900       => 'M15',
    1_800     => 'M30',
    3_600     => 'H1',
    7_200     => 'H2',
    10_800    => 'H3',
    14_400    => 'H4',
    21_600    => 'H6',
    28_800    => 'H8',
    43_200    => 'H12',
    86_400    => 'D',
    604_800   => 'W',
    2_678_400 => 'M'
  }.freeze

  TRIGGER_CONDITION = {
    'DEFAULT' => { long: 'ask', short: 'bid' },
    'INVERSE' => { long: 'bid', short: 'ask' },
    'BID'     => { long: 'bid', short: 'bid' },
    'ASK'     => { long: 'ask', short: 'ask' },
    'MID'     => { long: 'mid', short: 'mid' }
  }.freeze

  INSTRUMENTS = {
    # Forex.
    'AUD_CAD' => {
      'instrument' => 'AUD_CAD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00007833
    },
    'AUD_CHF' => {
      'instrument' => 'AUD_CHF',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.0001062
    },
    'AUD_HKD' => {
      'instrument' => 'AUD_HKD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00001279
    },
    'AUD_JPY' => {
      'instrument' => 'AUD_JPY',
      'pip_size'   => 0.01,
      'pip_price'  => 0.00008816
    },
    'AUD_NZD' => {
      'instrument' => 'AUD_NZD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00007356
    },
    'AUD_SGD' => {
      'instrument' => 'AUD_SGD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00007653
    },
    'AUD_USD' => {
      'instrument' => 'AUD_USD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.0001,
      'exchange'   => 0.71
    },
    'CAD_CHF' => {
      'instrument' => 'CAD_CHF',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.0001
    },
    'CAD_HKD' => {
      'instrument' => 'CAD_HKD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00001279
    },
    'CAD_JPY' => {
      'instrument' => 'CAD_JPY',
      'pip_size'   => 0.01,
      'pip_price'  => 0.00008816
    },
    'CAD_SGD' => {
      'instrument' => 'CAD_SGD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00007653
    },
    'CHF_HKD' => {
      'instrument' => 'CHF_HKD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00001279
    },
    'CHF_JPY' => {
      'instrument' => 'CHF_JPY',
      'pip_size'   => 0.01,
      'pip_price'  => 0.00008816
    },
    'CHF_ZAR' => {
      'instrument' => 'CHF_ZAR',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00000842
    },
    'EUR_AUD' => {
      'instrument' => 'EUR_AUD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00007647
    },
    'EUR_CAD' => {
      'instrument' => 'EUR_CAD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00008117
    },
    'EUR_CHF' => {
      'instrument' => 'EUR_CHF',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00010614
    },
    'EUR_CZK' => {
      'instrument' => 'EUR_CZK',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00000489
    },
    'EUR_DKK' => {
      'instrument' => 'EUR_DKK',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00001667
    },
    'EUR_GBP' => {
      'instrument' => 'EUR_GBP',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00013245
    },
    'EUR_HKD' => {
      'instrument' => 'EUR_HKD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00001279
    },
    'EUR_HUF' => {
      'instrument' => 'EUR_HUF',
      'pip_size'   => 0.01,
      'pip_price'  => 0.00004012
    },
    'EUR_JPY' => {
      'instrument' => 'EUR_JPY',
      'pip_size'   => 0.01,
      'pip_price'  => 0.00008816
    },
    'EUR_NOK' => {
      'instrument' => 'EUR_NOK',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00001294
    },
    'EUR_NZD' => {
      'instrument' => 'EUR_NZD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00007356
    },
    'EUR_PLN' => {
      'instrument' => 'EUR_PLN',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00002992
    },
    'EUR_SEK' => {
      'instrument' => 'EUR_SEK',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00001265
    },
    'EUR_SGD' => {
      'instrument' => 'EUR_SGD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00007655
    },
    'EUR_TRY' => {
      'instrument' => 'EUR_TRY',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00002668
    },
    'EUR_USD' => {
      'instrument' => 'EUR_USD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.0001,
      'exchange'   => 1.15
    },
    'EUR_ZAR' => {
      'instrument' => 'EUR_ZAR',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00000842
    },
    'GBP_AUD' => {
      'instrument' => 'GBP_AUD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00008078
    },
    'GBP_CAD' => {
      'instrument' => 'GBP_CAD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.0000812
    },
    'GBP_CHF' => {
      'instrument' => 'GBP_CHF',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00010616
    },
    'GBP_HKD' => {
      'instrument' => 'GBP_HKD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00001279
    },
    'GBP_USD' => {
      'instrument' => 'GBP_USD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.0001,
      'exchange'   => 1.30
    },
    'GBP_ZAR' => {
      'instrument' => 'GBP_ZAR',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00000842
    },
    'GBP_JPY' => {
      'instrument' => 'GBP_JPY',
      'pip_size'   => 0.01,
      'pip_price'  => 0.00008807
    },
    'GBP_NZD' => {
      'instrument' => 'GBP_NZD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00007358
    },
    'GBP_PLN' => {
      'instrument' => 'GBP_PLN',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00002993
    },
    'GBP_SGD' => {
      'instrument' => 'GBP_SGD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00007655
    },
    'HKD_JPY' => {
      'instrument' => 'HKD_JPY',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00000089
    },
    'NZD_CAD' => {
      'instrument' => 'NZD_CAD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00008119
    },
    'NZD_CHF' => {
      'instrument' => 'NZD_CHF',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00010616
    },
    'NZD_HKD' => {
      'instrument' => 'NZD_HKD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00001279
    },
    'NZD_JPY' => {
      'instrument' => 'NZD_JPY',
      'pip_size'   => 0.01,
      'pip_price'  => 0.00008764
    },
    'NZD_SGD' => {
      'instrument' => 'NZD_SGD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00007655
    },
    'NZD_USD' => {
      'instrument' => 'NZD_USD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.0001,
      'exchange'   => 0.66
    },
    'SGD_CHF' => {
      'instrument' => 'SGD_CHF',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00010616
    },
    'SGD_HKD' => {
      'instrument' => 'SGD_HKD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00001279
    },
    'SGD_JPY' => {
      'instrument' => 'SGD_JPY',
      'pip_size'   => 0.01,
      'pip_price'  => 0.00008816
    },
    'TRY_JPY' => {
      'instrument' => 'TRY_JPY',
      'pip_size'   => 0.01,
      'pip_price'  => 0.00008816
    },
    'USD_CAD' => {
      'instrument' => 'USD_CAD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00008219,
      'exchange'   => 1.31
    },
    'USD_CHF' => {
      'instrument' => 'USD_CHF',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00010619,
      'exchange'   => 1.00
    },
    'USD_CNH' => {
      'instrument' => 'USD_CNH',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00001583,
      'exchange'   => 6.93
    },
    'USD_CZK' => {
      'instrument' => 'USD_CZK',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00000489,
      'exchange'   => 22.52
    },
    'USD_DKK' => {
      'instrument' => 'USD_DKK',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00001668,
      'exchange'   => 6.50
    },
    'USD_HKD' => {
      'instrument' => 'USD_HKD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00001279,
      'exchange'   => 7.84
    },
    'USD_HUF' => {
      'instrument' => 'USD_HUF',
      'pip_size'   => 0.01,
      'pip_price'  => 0.00004013,
      'exchange'   => 281.44
    },
    'USD_INR' => {
      'instrument' => 'USD_INR',
      'pip_size'   => 0.01,
      'pip_price'  => 0.00015745,
      'exchange'   => 73.50
    },
    'USD_JPY' => {
      'instrument' => 'USD_JPY',
      'pip_size'   => 0.01,
      'pip_price'  => 0.00008823,
      'exchange'   => 112.79
    },
    'USD_MXN' => {
      'instrument' => 'USD_MXN',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00000542,
      'exchange'   => 19.32
    },
    'USD_NOK' => {
      'instrument' => 'USD_NOK',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00001294,
      'exchange'   => 8.25
    },
    'USD_PLN' => {
      'instrument' => 'USD_PLN',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00002992,
      'exchange'   => 3.74
    },
    'USD_SAR' => {
      'instrument' => 'USD_SAR',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00002665,
      'exchange'   => 3.75
    },
    'USD_SEK' => {
      'instrument' => 'USD_SEK',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00001265,
      'exchange'   => 8.99
    },
    'USD_SGD' => {
      'instrument' => 'USD_SGD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00007655,
      'exchange'   => 1.38
    },
    'USD_THB' => {
      'instrument' => 'USD_THB',
      'pip_size'   => 0.01,
      'pip_price'  => 0.00031755,
      'exchange'   => 32.76
    },
    'USD_TRY' => {
      'instrument' => 'USD_TRY',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.0000267,
      'exchange'   => 5.66
    },
    'USD_ZAR' => {
      'instrument' => 'USD_ZAR',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00000843,
      'exchange'   => 14.27
    },
    'ZAR_JPY' => {
      'instrument' => 'ZAR_JPY',
      'pip_size'   => 0.01,
      'pip_price'  => 0.00008816
    },

    # Metals.
    'XAG_AUD' => {
      'instrument' => 'XAG_AUD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00008074
    },
    'XAG_CAD' => {
      'instrument' => 'XAG_CAD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00008119
    },
    'XAG_CHF' => {
      'instrument' => 'XAG_CHF',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.0001061
    },
    'XAG_EUR' => {
      'instrument' => 'XAG_EUR',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00012415
    },
    'XAG_GBP' => {
      'instrument' => 'XAG_GBP',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00014267
    },
    'XAG_HKD' => {
      'instrument' => 'XAG_HKD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00001279
    },
    'XAG_JPY' => {
      'instrument' => 'XAG_JPY',
      'pip_size'   => 1.0,
      'pip_price'  => 0.008878
    },
    'XAG_NZD' => {
      'instrument' => 'XAG_NZD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00007362
    },
    'XAG_SGD' => {
      'instrument' => 'XAG_SGD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.00007655
    },
    'XAG_USD' => {
      'instrument' => 'XAG_USD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.0001
    },
    'XAU_AUD' => {
      'instrument' => 'XAU_AUD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.0080752
    },
    'XAU_CAD' => {
      'instrument' => 'XAU_CAD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.00811906
    },
    'XAU_CHF' => {
      'instrument' => 'XAU_CHF',
      'pip_size'   => 0.01,
      'pip_price'  => 0.01060985
    },
    'XAU_EUR' => {
      'instrument' => 'XAU_EUR',
      'pip_size'   => 0.01,
      'pip_price'  => 0.012416
    },
    'XAU_GBP' => {
      'instrument' => 'XAU_GBP',
      'pip_size'   => 0.01,
      'pip_price'  => 0.0142713
    },
    'XAU_HKD' => {
      'instrument' => 'XAU_HKD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.00127913
    },
    'XAU_JPY' => {
      'instrument' => 'XAU_JPY',
      'pip_size'   => 1.0,
      'pip_price'  => 0.088778
    },
    'XAU_NZD' => {
      'instrument' => 'XAU_NZD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.0073625
    },
    'XAU_SGD' => {
      'instrument' => 'XAU_SGD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.00765433
    },
    'XAU_USD' => {
      'instrument' => 'XAU_USD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.01
    },
    'XAU_XAG' => {
      'instrument' => 'XAU_XAG',
      'pip_size'   => 0.01,
      'pip_price'  => 0.1755333
    },
    'XCU_USD' => {
      'instrument' => 'XCU_USD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.0001
    },
    'XPD_USD' => {
      'instrument' => 'XPD_USD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.01
    },
    'XPT_USD' => {
      'instrument' => 'XPT_USD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.01
    },

    # Bonds.
    'DE10YB_EUR' => {
      'instrument' => 'DE10YB_EUR',
      'pip_size'   => 0.01,
      'pip_price'  => 0.0124057
    },
    'UK10YB_GBP' => {
      'instrument' => 'UK10YB_GBP',
      'pip_size'   => 0.01,
      'pip_price'  => 0.0142585
    },
    'USB02Y_USD' => {
      'instrument' => 'USB02Y_USD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.01
    },
    'USB05Y_USD' => {
      'instrument' => 'USB05Y_USD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.01
    },
    'USB10Y_USD' => {
      'instrument' => 'USB10Y_USD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.01
    },
    'USB30Y_USD' => {
      'instrument' => 'USB30Y_USD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.01
    },

    # Indices.
    'AU200_AUD' => {
      'instrument' => 'AU200_AUD',
      'pip_size'   => 1.0,
      'pip_price'  => 0.80732
    },
    'CH20_CHF' => {
      'instrument' => 'CH20_CHF',
      'pip_size'   => 1.0,
      'pip_price'  => 1.06076035
    },
    'CN50_USD' => {
      'instrument' => 'CN50_USD',
      'pip_size'   => 1.0,
      'pip_price'  => 1.0
    },
    'DE30_EUR' => {
      'instrument' => 'DE30_EUR',
      'pip_size'   => 1.0,
      'pip_price'  => 1.16327
    },
    'EU50_EUR' => {
      'instrument' => 'EU50_EUR',
      'pip_size'   => 1.0,
      'pip_price'  => 1.1606
    },
    'FR40_EUR' => {
      'instrument' => 'FR40_EUR',
      'pip_size'   => 1.0,
      'pip_price'  => 1.1606
    },
    'HK33_HKD' => {
      'instrument' => 'HK33_HKD',
      'pip_size'   => 1.0,
      'pip_price'  => 0.1281496
    },
    'IN50_USD' => {
      'instrument' => 'IN50_USD',
      'pip_size'   => 1.0,
      'pip_price'  => 1.0
    },
    'JP225_USD' => {
      'instrument' => 'JP225_USD',
      'pip_size'   => 1.0,
      'pip_price'  => 1.0
    },
    'NL25_EUR' => {
      'instrument' => 'NL25_EUR',
      'pip_size'   => 0.01,
      'pip_price'  => 0.011606
    },
    'SG30_SGD' => {
      'instrument' => 'SG30_SGD',
      'pip_size'   => 0.1,
      'pip_price'  => 0.07323164
    },
    'UK100_GBP' => {
      'instrument' => 'UK100_GBP',
      'pip_size'   => 1.0,
      'pip_price'  => 1.30713
    },
    'US2000_USD' => {
      'instrument' => 'US2000_USD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.01
    },
    'US30_USD' => {
      'instrument' => 'US30_USD',
      'pip_size'   => 1.0,
      'pip_price'  => 1.0
    },
    'NAS100_USD' => {
      'instrument' => 'NAS100_USD',
      'pip_size'   => 1.0,
      'pip_price'  => 1.0
    },
    'SPX500_USD' => {
      'instrument' => 'SPX500_USD',
      'pip_size'   => 1.0,
      'pip_price'  => 1.0
    },
    'TWIX_USD' => {
      'instrument' => 'TWIX_USD',
      'pip_size'   => 1.0,
      'pip_price'  => 1.0
    },

    # Commodities.
    'BCO_USD' => {
      'instrument' => 'BCO_USD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.01
    },
    'CORN_USD' => {
      'instrument' => 'CORN_USD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.01
    },
    'NATGAS_USD' => {
      'instrument' => 'NATGAS_USD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.01
    },
    'SOYBN_USD' => {
      'instrument' => 'SOYBN_USD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.01
    },
    'SUGAR_USD' => {
      'instrument' => 'SUGAR_USD',
      'pip_size'   => 0.0001,
      'pip_price'  => 0.0001
    },
    'WHEAT_USD' => {
      'instrument' => 'WHEAT_USD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.01
    },
    'WTICO_USD' => {
      'instrument' => 'WTICO_USD',
      'pip_size'   => 0.01,
      'pip_price'  => 0.01
    }
  }.freeze
end
