## Setup

1. **Run Docker and Initialize Database**:
   
   ```sh
   ./init_db.sh

   docker volume create pgdata # (you may need to create this volume)
   ```
   
2. **Start the Application**:
   
   ```sh
   cargo run
   ```

3. **Connect to DB**
   
   ```sh
   psql -h localhost -p 5433 -U postgres -d replic8
   ```

4. **Do any DB insert/update/delete operation**


