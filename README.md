# ♟️ PostgreSQL Chess Engine

W pełni funkcjonalny silnik szachowy napisany w 100% w bazie danych PostgreSQL (PL/pgSQL). Projekt udowadnia, że relacyjna baza danych może służyć nie tylko do przechowywania stanu, ale również do rygorystycznego egzekwowania skomplikowanej logiki biznesowej i geometrycznej.

## 🚀 Funkcjonalności (Features)
* **Pełna walidacja ruchów:** Silnik odrzuca nielegalne ruchy na poziomie pojedynczej transakcji bazodanowej.
* **Zaawansowana geometria i Raycasting:** Wykrywanie kolizji na dwuwymiarowej tablicy (figury nie przenikają przez siebie).
* **Ochrona Króla (Szach/Mat):** Silnik wykonuje wirtualną symulację ruchu w pamięci RAM i skanuje planszę "odwróconym radarem", aby zablokować ruchy odsłaniające króla na atak.
* **Mechaniki specjalne FIDE:** Pełna obsługa Roszady, Promocji Piona oraz Bicia w przelocie (En Passant).
* **Generowanie widoku:** Funkcja rysująca aktualny stan szachownicy w czytelnym formacie tekstowym bezpośrednio z zapytania `SELECT`.

## 🛠️ Architektura i Technologie
* **Baza danych:** PostgreSQL
* **Logika:** PL/pgSQL (Procedury składowane, Funkcje, Widoki)
* **Infrastruktura:** Docker & Docker Compose (w pełni zautomatyzowana inicjalizacja środowiska z folderu `init-scripts`)

## 🎮 Jak zagrać?
1. Uruchom kontener z bazą: 
   `docker-compose up -d`
2. Podłącz się dowolnym klientem SQL (np. DBeaver) do bazy na porcie `5433` (użytkownik: `chess_admin`, hasło: `SuperTajneHaslo123`).
3. Stwórz nową grę za pomocą zapytania:
   ```sql
   SELECT utworz_nowa_gre('Gracz 1', 'Gracz 2');
