CREATE TABLE partie_szachowe(
    id SERIAL PRIMARY KEY,
    bialy_gracz TEXT DEFAULT 'Gracz 1',
    czarny_gracz TEXT DEFAULT 'Gracz 2',
    plansza TEXT[8][8],
    czyja_tura TEXT CHECK (czyja_tura IN ('bialy', 'czarny')) DEFAULT 'bialy',
    mozliwa_roszada_biala_dluga BOOLEAN DEFAULT TRUE,
    mozliwa_roszada_biala_krotka BOOLEAN DEFAULT TRUE,
    mozliwa_roszada_czarna_dluga BOOLEAN DEFAULT TRUE,
    mozliwa_roszada_czarna_krotka BOOLEAN DEFAULT TRUE,
    bicie_w_przelocie_cel TEXT DEFAULT NULL,
    polruchy INTEGER DEFAULT 0,
    numer_pelnego_ruchu INTEGER DEFAULT 1,
    ostatnia_aktualizacja TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);