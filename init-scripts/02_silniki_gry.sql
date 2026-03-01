CREATE OR REPLACE FUNCTION rysuj_plansze(p_plansza TEXT[][]) 
RETURNS TEXT AS $$
DECLARE
    wynik TEXT := E'\n';
    rzad INTEGER;
    kolumna INTEGER;
    pole TEXT;
BEGIN
    FOR rzad IN 1..8 LOOP
        wynik := wynik || (9 - rzad)::TEXT || ' | ';
        FOR kolumna IN 1..8 LOOP
            pole := p_plansza[rzad][kolumna];
            IF pole = '' OR pole IS NULL THEN
                wynik := wynik || '. ';
            ELSE
                wynik := wynik || pole || ' ';
            END IF;
        END LOOP;
        
        wynik := wynik || E'\n'
    END LOOP;
    wynik := wynik || '  -----------------' || E'\n';
    wynik := wynik || '    a b c d e f g h';
    RETURN wynik;
END;
$$ LANGUAGE plpgsql IMMUTABLE;


CREATE OR REPLACE VIEW v_podglad_planszy AS
SELECT 
    id AS id_gry,
    bialy_gracz || ' (Białe) vs ' || czarny_gracz || ' (Czarne)' AS gracze,
    czyja_tura,
    numer_pelnego_ruchu AS numer_ruchu,
    rysuj_plansze(plansza) AS szachownica
FROM partie_szachowe;


CREATE OR REPLACE FUNCTION pozycja_na_indeks(p_pozycja TEXT) 
RETURNS INTEGER[] AS $$
DECLARE
    kolumna INTEGER;
    rzad INTEGER;
BEGIN
    kolumna := ascii(lower(substring(p_pozycja FROM 1 FOR 1))) - 96;
    rzad := 9 - cast(substring(p_pozycja FROM 2 FOR 1) AS INTEGER);
    RETURN ARRAY[rzad, kolumna];
END;
$$ LANGUAGE plpgsql IMMUTABLE;



CREATE OR REPLACE FUNCTION utworz_nowa_gre(gracz_bialy TEXT, gracz_czarny TEXT) 
RETURNS INTEGER AS $$
DECLARE
    nowe_id_gry INTEGER;
BEGIN
    INSERT INTO partie_szachowe (bialy_gracz, czarny_gracz, plansza)
    VALUES (
        gracz_bialy, 
        gracz_czarny, 
        ARRAY[
            ['r', 'n', 'b', 'q', 'k', 'b', 'n', 'r'],
            ['p', 'p', 'p', 'p', 'p', 'p', 'p', 'p'],
            ['', '', '', '', '', '', '', ''],
            ['', '', '', '', '', '', '', ''],
            ['', '', '', '', '', '', '', ''],
            ['', '', '', '', '', '', '', ''],
            ['P', 'P', 'P', 'P', 'P', 'P', 'P', 'P'],
            ['R', 'N', 'B', 'Q', 'K', 'B', 'N', 'R']
        ]
    ) RETURNING id INTO nowe_id_gry;
    RETURN nowe_id_gry;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION public.czy_wlasciwy_kolor(figura text, czyja_tura text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
begin
	return (czyja_tura = 'bialy' and figura ~'^[A-Z]$')
		or (czyja_tura = 'czarny' and figura ~'^[a-z]$');
end;
$function$
;


CREATE OR REPLACE FUNCTION public.czy_geometria_ok(figura text, start_r integer, start_k integer, cel_r integer, cel_k integer, czy_bicie boolean)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
begin
	case
		when figura in ('r', 'R') then
			return (start_r = cel_r or start_k = cel_k);
		when figura in ('n', 'N') then
			return (abs(start_r - cel_r) = 2 and abs(start_k - cel_k) = 1) -- skok pionowy
				or (abs(start_k - cel_k) = 2 and abs(start_r - cel_r) = 1); -- skok poziomy
		when figura in ('b', 'B') then
			return abs(cel_r - start_r) = abs(cel_k - start_k);
		when figura = 'P' then
			if czy_bicie = false then
				if start_r = 7 then
					return (((start_r - cel_r) between 1 and 2) and start_k = cel_k);
				else
					return ((start_r - cel_r) = 1 and start_k = cel_k);
				end if;
			else
				return (start_r - cel_r = 1 and abs(start_k - cel_k) = 1);
			end if;
		when figura = 'p' then
			if czy_bicie = false then
				if start_r = 2 then
					return (((cel_r - start_r) between 1 and 2) and start_k = cel_k);
				else
					return ((cel_r - start_r) = 1 and start_k = cel_k);
				end if;
			else
				return (cel_r - start_r = 1 and abs(start_k - cel_k) = 1);
			end if;
		when figura in ('q', 'Q') then
			return (start_r = cel_r or start_k = cel_k)
				or (abs(cel_r - start_r) = abs(cel_k - start_k));
		when figura in ('k', 'K') then
			return (abs(start_k - cel_k) <= 1 and abs(cel_r - start_r) <= 1)
			OR (abs(start_k - cel_k) = 2 AND start_r = cel_r);
		else return false;
		end case;		
end;
$function$
;


CREATE OR REPLACE FUNCTION public.czy_droga_wolna(p_plansza text[], start_r integer, start_k integer, cel_r integer, cel_k integer)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
declare
	krok_r int;
	krok_k int;
	ruch_r int;
	ruch_k int;
begin
	krok_r := sign(cel_r - start_r)::int;
	krok_k := sign(cel_k - start_k)::int;
	ruch_r := start_r + krok_r;
	ruch_k := start_k + krok_k;

	while (ruch_r <> cel_r and ruch_k <> cel_k) loop
		if p_plansza[ruch_r][ruch_k] <> '' and p_plansza[ruch_r][ruch_k] is not null then
			return false;
		end if;

		ruch_r := ruch_r + krok_r;
		ruch_k := ruch_k + krok_k;
	end loop;

	return true;
end;
$function$
;


CREATE OR REPLACE FUNCTION czy_pole_atakowane(
    p_plansza TEXT[][], 
    cel_r INT, cel_k INT, 
    kolor_atakujacego TEXT
) RETURNS BOOLEAN AS $$
DECLARE
    w_pion TEXT; w_skoczek TEXT; w_goniec TEXT; w_wieza TEXT; w_hetman TEXT; w_krol TEXT;
    i INT;
    sprawdz_r INT; sprawdz_k INT;
    figura TEXT;
    skoki_r INT[] := ARRAY[2, 2, -2, -2, 1, 1, -1, -1];
    skoki_k INT[] := ARRAY[1, -1, 1, -1, 2, -2, 2, -2];
    kroki_krola_r INT[] := ARRAY[1, 1, 1, 0, 0, -1, -1, -1];
    kroki_krola_k INT[] := ARRAY[1, 0, -1, 1, -1, 1, 0, -1];
    promienie_r INT[] := ARRAY[1, -1, 0, 0, 1, 1, -1, -1];
    promienie_k INT[] := ARRAY[0, 0, 1, -1, 1, -1, 1, -1];
BEGIN
    IF kolor_atakujacego = 'bialy' THEN
        w_pion := 'P'; w_skoczek := 'N'; w_goniec := 'B'; w_wieza := 'R'; w_hetman := 'Q'; w_krol := 'K';
    ELSE
        w_pion := 'p'; w_skoczek := 'n'; w_goniec := 'b'; w_wieza := 'r'; w_hetman := 'q'; w_krol := 'k';
    END IF;
    FOR i IN 1..8 LOOP
        sprawdz_r := cel_r + skoki_r[i];
        sprawdz_k := cel_k + skoki_k[i];
        IF sprawdz_r BETWEEN 1 AND 8 AND sprawdz_k BETWEEN 1 AND 8 THEN
            IF p_plansza[sprawdz_r][sprawdz_k] = w_skoczek THEN RETURN TRUE; END IF;
        END IF;
    END LOOP;
    FOR i IN 1..8 LOOP
        sprawdz_r := cel_r + kroki_krola_r[i];
        sprawdz_k := cel_k + kroki_krola_k[i];
        IF sprawdz_r BETWEEN 1 AND 8 AND sprawdz_k BETWEEN 1 AND 8 THEN
            IF p_plansza[sprawdz_r][sprawdz_k] = w_krol THEN RETURN TRUE; END IF;
        END IF;
    END LOOP;
    IF kolor_atakujacego = 'bialy' THEN
        sprawdz_r := cel_r + 1; -- Białe piony w naszej tablicy atakują z dołu do góry
    ELSE
        sprawdz_r := cel_r - 1; -- Czarne atakują z góry na dół
    END IF;
    
    IF sprawdz_r BETWEEN 1 AND 8 THEN
        IF cel_k - 1 >= 1 THEN
            IF p_plansza[sprawdz_r][cel_k - 1] = w_pion THEN RETURN TRUE; END IF;
        END IF;
        IF cel_k + 1 <= 8 THEN
            IF p_plansza[sprawdz_r][cel_k + 1] = w_pion THEN RETURN TRUE; END IF;
        END IF;
    END IF;
    FOR i IN 1..8 LOOP
        sprawdz_r := cel_r + promienie_r[i];
        sprawdz_k := cel_k + promienie_k[i];
        
        WHILE sprawdz_r BETWEEN 1 AND 8 AND sprawdz_k BETWEEN 1 AND 8 LOOP
            figura := p_plansza[sprawdz_r][sprawdz_k];
            
            IF figura != '' AND figura IS NOT NULL THEN
                IF i <= 4 THEN 
                    IF figura = w_wieza OR figura = w_hetman THEN RETURN TRUE; END IF;
                ELSE 
                    IF figura = w_goniec OR figura = w_hetman THEN RETURN TRUE; END IF;
                END IF;
                EXIT; 
            END IF;
            sprawdz_r := sprawdz_r + promienie_r[i];
            sprawdz_k := sprawdz_k + promienie_k[i];
        END LOOP;
    END LOOP;
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;


CREATE OR REPLACE FUNCTION wykonaj_ruch(p_id_gry INTEGER, p_skad TEXT, p_dokad TEXT)
RETURNS TEXT AS $$
DECLARE
    v_skad_idx INTEGER[]; v_dokad_idx INTEGER[];
    v_figura_start TEXT; v_figura_cel TEXT;
    v_czyja_tura TEXT; v_kolor_przeciwnika TEXT; v_szukany_krol TEXT;
    v_plansza TEXT[][]; v_symulacja_planszy TEXT[][];
    v_czy_bicie BOOLEAN; v_czy_roszada BOOLEAN := FALSE; v_czy_en_passant BOOLEAN := FALSE;
    
    v_rosz_bk BOOLEAN; v_rosz_bd BOOLEAN; v_rosz_ck BOOLEAN; v_rosz_cd BOOLEAN;
    v_kolumna_przelotu INTEGER; v_nowa_kolumna_przelotu INTEGER := NULL;
    
    v_krol_r INT; v_krol_k INT; r INT; k INT;
BEGIN
    v_skad_idx := pozycja_na_indeks(p_skad);
    v_dokad_idx := pozycja_na_indeks(p_dokad);

    SELECT plansza, czyja_tura, mozliwa_roszada_biala_krotka, mozliwa_roszada_biala_dluga, mozliwa_roszada_czarna_krotka, mozliwa_roszada_czarna_dluga, kolumna_przelotu
    INTO v_plansza, v_czyja_tura, v_rosz_bk, v_rosz_bd, v_rosz_ck, v_rosz_cd, v_kolumna_przelotu
    FROM partie_szachowe WHERE id = p_id_gry FOR UPDATE;

    IF v_czyja_tura = 'bialy' THEN v_kolor_przeciwnika := 'czarny'; v_szukany_krol := 'K';
    ELSE v_kolor_przeciwnika := 'bialy'; v_szukany_krol := 'k'; END IF;

    v_figura_start := v_plansza[v_skad_idx[1]][v_skad_idx[2]];
    v_figura_cel := v_plansza[v_dokad_idx[1]][v_dokad_idx[2]];
    v_czy_bicie := (v_figura_cel != '' AND v_figura_cel IS NOT NULL);

    -- ==========================================
    -- WYKRYWANIE BICIA W PRZELOCIE (En Passant)
    -- ==========================================
    IF lower(v_figura_start) = 'p' AND v_skad_idx[2] != v_dokad_idx[2] AND NOT v_czy_bicie THEN
        IF v_dokad_idx[2] = v_kolumna_przelotu THEN
            v_czy_bicie := TRUE;
            v_czy_en_passant := TRUE;
        END IF;
    END IF;

    -- ==========================================
    -- BRAMKI BEZPIECZEŃSTWA
    -- ==========================================
    IF v_figura_start = '' OR v_figura_start IS NULL THEN RAISE EXCEPTION 'Błąd: Pole % jest puste!', p_skad; END IF;
    IF NOT czy_wlasciwy_kolor(v_figura_start, v_czyja_tura) THEN RAISE EXCEPTION 'Błąd: To nie Twoja figura!'; END IF;
    IF v_czy_bicie AND NOT v_czy_en_passant AND czy_wlasciwy_kolor(v_figura_cel, v_czyja_tura) THEN RAISE EXCEPTION 'Błąd: Friendly fire!'; END IF;
    IF NOT czy_geometria_ok(v_figura_start, v_skad_idx[1], v_skad_idx[2], v_dokad_idx[1], v_dokad_idx[2], v_czy_bicie) THEN 
        RAISE EXCEPTION 'Błąd: Niepoprawny ruch geometryczny!'; 
    END IF;

    -- Detekcja roszady
    IF lower(v_figura_start) = 'k' AND abs(v_skad_idx[2] - v_dokad_idx[2]) = 2 THEN v_czy_roszada := TRUE; END IF;

    -- Detekcja kolizji (Pomijamy Skoczka i Roszadę)
    IF lower(v_figura_start) != 'n' AND NOT v_czy_roszada THEN
        IF NOT czy_droga_wolna(v_plansza, v_skad_idx[1], v_skad_idx[2], v_dokad_idx[1], v_dokad_idx[2]) THEN RAISE EXCEPTION 'Błąd: Droga jest zablokowana!'; END IF;
    END IF;

    -- ==========================================
    -- TWORZENIE BRUDNOPISU DO SYMULACJI
    -- ==========================================
    v_symulacja_planszy := v_plansza;
    v_symulacja_planszy[v_skad_idx[1]][v_skad_idx[2]] := ''; -- Podnosimy figurę ze startu

    -- OBSŁUGA EN PASSANT
    IF v_czy_en_passant THEN
        IF v_figura_start = 'P' THEN v_symulacja_planszy[v_dokad_idx[1] + 1][v_dokad_idx[2]] := ''; -- Zabij czarnego piona pod nami
        ELSE v_symulacja_planszy[v_dokad_idx[1] - 1][v_dokad_idx[2]] := ''; -- Zabij białego piona nad nami
        END IF;
    END IF;

    -- PROMOCJA PIONA LUB ZWYKŁY RUCH
    IF v_figura_start = 'P' AND v_dokad_idx[1] = 1 THEN
        v_symulacja_planszy[v_dokad_idx[1]][v_dokad_idx[2]] := 'Q'; v_figura_start := 'Q';
    ELSIF v_figura_start = 'p' AND v_dokad_idx[1] = 8 THEN
        v_symulacja_planszy[v_dokad_idx[1]][v_dokad_idx[2]] := 'q'; v_figura_start := 'q';
    ELSE
        v_symulacja_planszy[v_dokad_idx[1]][v_dokad_idx[2]] := v_figura_start;
    END IF;

    -- ==========================================
    -- SPECJALNA WALIDACJA ROSZADY
    -- ==========================================
    IF v_czy_roszada THEN
        IF p_dokad = 'g1' THEN
            IF NOT v_rosz_bk THEN RAISE EXCEPTION 'Błąd: Utracono prawo do roszady!'; END IF;
            IF v_plansza[8][6] != '' OR v_plansza[8][7] != '' THEN RAISE EXCEPTION 'Błąd: Droga zajęta!'; END IF;
            IF czy_pole_atakowane(v_plansza, 8, 5, 'czarny') OR czy_pole_atakowane(v_plansza, 8, 6, 'czarny') THEN RAISE EXCEPTION 'Błąd: Szach!'; END IF;
            v_symulacja_planszy[8][6] := 'R'; v_symulacja_planszy[8][8] := ''; 
        ELSIF p_dokad = 'c1' THEN
            IF NOT v_rosz_bd THEN RAISE EXCEPTION 'Błąd: Utracono prawo do roszady!'; END IF;
            IF v_plansza[8][2] != '' OR v_plansza[8][3] != '' OR v_plansza[8][4] != '' THEN RAISE EXCEPTION 'Błąd: Droga zajęta!'; END IF;
            IF czy_pole_atakowane(v_plansza, 8, 5, 'czarny') OR czy_pole_atakowane(v_plansza, 8, 4, 'czarny') THEN RAISE EXCEPTION 'Błąd: Szach!'; END IF;
            v_symulacja_planszy[8][4] := 'R'; v_symulacja_planszy[8][1] := '';
        ELSIF p_dokad = 'g8' THEN
            IF NOT v_rosz_ck THEN RAISE EXCEPTION 'Błąd: Utracono prawo do roszady!'; END IF;
            IF v_plansza[1][6] != '' OR v_plansza[1][7] != '' THEN RAISE EXCEPTION 'Błąd: Droga zajęta!'; END IF;
            IF czy_pole_atakowane(v_plansza, 1, 5, 'bialy') OR czy_pole_atakowane(v_plansza, 1, 6, 'bialy') THEN RAISE EXCEPTION 'Błąd: Szach!'; END IF;
            v_symulacja_planszy[1][6] := 'r'; v_symulacja_planszy[1][8] := '';
        ELSIF p_dokad = 'c8' THEN
            IF NOT v_rosz_cd THEN RAISE EXCEPTION 'Błąd: Utracono prawo do roszady!'; END IF;
            IF v_plansza[1][2] != '' OR v_plansza[1][3] != '' OR v_plansza[1][4] != '' THEN RAISE EXCEPTION 'Błąd: Droga zajęta!'; END IF;
            IF czy_pole_atakowane(v_plansza, 1, 5, 'bialy') OR czy_pole_atakowane(v_plansza, 1, 4, 'bialy') THEN RAISE EXCEPTION 'Błąd: Szach!'; END IF;
            v_symulacja_planszy[1][4] := 'r'; v_symulacja_planszy[1][1] := '';
        ELSE RAISE EXCEPTION 'Błąd: Nierozpoznany format roszady!'; END IF;
    END IF;

    -- ==========================================
    -- WALIDACJA SZACHA 
    -- ==========================================
    FOR r IN 1..8 LOOP 
        FOR k IN 1..8 LOOP 
            IF v_symulacja_planszy[r][k] = v_szukany_krol THEN v_krol_r := r; v_krol_k := k; EXIT; END IF; 
        END LOOP; 
        EXIT WHEN v_krol_r IS NOT NULL; 
    END LOOP;

    IF czy_pole_atakowane(v_symulacja_planszy, v_krol_r, v_krol_k, v_kolor_przeciwnika) THEN 
        RAISE EXCEPTION 'Błąd: Ten ruch odsłania Twojego Króla na Szacha!'; 
    END IF;

    IF v_figura_start = 'K' THEN v_rosz_bk := FALSE; v_rosz_bd := FALSE; ELSIF v_figura_start = 'k' THEN v_rosz_ck := FALSE; v_rosz_cd := FALSE; ELSIF v_figura_start = 'R' AND p_skad = 'h1' THEN v_rosz_bk := FALSE; ELSIF v_figura_start = 'R' AND p_skad = 'a1' THEN v_rosz_bd := FALSE; ELSIF v_figura_start = 'r' AND p_skad = 'h8' THEN v_rosz_ck := FALSE; ELSIF v_figura_start = 'r' AND p_skad = 'a8' THEN v_rosz_cd := FALSE; END IF;
    IF p_dokad = 'h1' THEN v_rosz_bk := FALSE; ELSIF p_dokad = 'a1' THEN v_rosz_bd := FALSE; ELSIF p_dokad = 'h8' THEN v_rosz_ck := FALSE; ELSIF p_dokad = 'a8' THEN v_rosz_cd := FALSE; END IF;

    IF lower(v_figura_start) = 'p' AND abs(v_skad_idx[1] - v_dokad_idx[1]) = 2 THEN 
        v_nowa_kolumna_przelotu := v_dokad_idx[2]; 
    END IF;

    UPDATE partie_szachowe
    SET plansza = v_symulacja_planszy, czyja_tura = v_kolor_przeciwnika, 
        numer_pelnego_ruchu = CASE WHEN v_czyja_tura = 'czarny' THEN numer_pelnego_ruchu + 1 ELSE numer_pelnego_ruchu END,
        mozliwa_roszada_biala_krotka = v_rosz_bk, mozliwa_roszada_biala_dluga = v_rosz_bd, 
        mozliwa_roszada_czarna_krotka = v_rosz_ck, mozliwa_roszada_czarna_dluga = v_rosz_cd,
        kolumna_przelotu = v_nowa_kolumna_przelotu
    WHERE id = p_id_gry;

    RETURN 'Sukces! Wykonano ruch: ' || p_skad || ' na ' || p_dokad;
END;
$$ LANGUAGE plpgsql;