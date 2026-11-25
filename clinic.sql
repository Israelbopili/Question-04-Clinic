-- ICT371 QUESTION 4: CLINIC APPOINTMENT SCHEDULING
DROP SCHEMA IF EXISTS q4_clinic CASCADE;
CREATE SCHEMA q4_clinic;
SET search_path TO q4_clinic;

CREATE TABLE patients(patient_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,full_name VARCHAR(120) NOT NULL);
CREATE TABLE doctors(doctor_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,full_name VARCHAR(120) NOT NULL);
CREATE TABLE appointments(
 appointment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 patient_id BIGINT NOT NULL REFERENCES patients(patient_id),
 doctor_id BIGINT NOT NULL REFERENCES doctors(doctor_id),
 appointment_day DATE NOT NULL,
 slot_time TIME NOT NULL CHECK(slot_time IN ('09:00','10:00','11:00','12:00')),
 status VARCHAR(10) NOT NULL CHECK(status IN ('BOOKED','ATTENDED','CANCELLED'))
);
CREATE TABLE clinic_summary(
 summary_date DATE PRIMARY KEY,booked_count BIGINT NOT NULL,
 attended_count BIGINT NOT NULL,cancelled_count BIGINT NOT NULL
);
INSERT INTO patients(full_name) VALUES('Patient One'),('Patient Two'),('Patient Three');
INSERT INTO doctors(full_name) VALUES('Doctor One'),('Doctor Two'),('Doctor Three');

CREATE OR REPLACE FUNCTION fn_daily_load(p_doctor_id BIGINT,p_day DATE)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_count BIGINT;
BEGIN
 PERFORM 1 FROM doctors WHERE doctor_id=p_doctor_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown doctor ID %',p_doctor_id; END IF;
 SELECT COUNT(*) INTO v_count FROM appointments
 WHERE doctor_id=p_doctor_id AND appointment_day=p_day AND status<>'CANCELLED';
 RETURN v_count;
END; $$;

CREATE OR REPLACE PROCEDURE pr_book_appointment(
 p_patient_id BIGINT,p_doctor_id BIGINT,p_day DATE,p_slot TIME
)
LANGUAGE plpgsql AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM patients WHERE patient_id=p_patient_id) THEN
  RAISE EXCEPTION 'Unknown patient ID %',p_patient_id;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM doctors WHERE doctor_id=p_doctor_id) THEN
  RAISE EXCEPTION 'Unknown doctor ID %',p_doctor_id;
 END IF;
 IF p_day IS NULL OR p_day<CURRENT_DATE THEN RAISE EXCEPTION 'Appointment date cannot be in the past'; END IF;
 IF p_slot IS NULL OR p_slot NOT IN ('09:00','10:00','11:00','12:00') THEN
  RAISE EXCEPTION 'Unsupported appointment slot';
 END IF;
 INSERT INTO appointments(patient_id,doctor_id,appointment_day,slot_time,status)
 VALUES(p_patient_id,p_doctor_id,p_day,p_slot,'BOOKED');
END; $$;

CREATE OR REPLACE FUNCTION fn_prevent_appointment_clash()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.status<>'CANCELLED' AND EXISTS(
  SELECT 1 FROM appointments a
  WHERE a.doctor_id=NEW.doctor_id AND a.appointment_day=NEW.appointment_day
    AND a.slot_time=NEW.slot_time AND a.status<>'CANCELLED'
    AND a.appointment_id IS DISTINCT FROM NEW.appointment_id
 ) THEN RAISE EXCEPTION 'Doctor already has a non-cancelled appointment in that slot'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER trg_prevent_appointment_clash
BEFORE INSERT OR UPDATE ON appointments
FOR EACH ROW EXECUTE FUNCTION fn_prevent_appointment_clash();

-- Six valid appointments across doctors and slots.
CALL pr_book_appointment(1,1,CURRENT_DATE,'09:00');
CALL pr_book_appointment(2,1,CURRENT_DATE,'10:00');
CALL pr_book_appointment(3,2,CURRENT_DATE,'09:00');
CALL pr_book_appointment(1,2,CURRENT_DATE,'11:00');
CALL pr_book_appointment(2,3,CURRENT_DATE,'09:00');
CALL pr_book_appointment(3,3,CURRENT_DATE,'12:00');

CREATE OR REPLACE VIEW v_today_appointments AS
SELECT a.appointment_day,p.full_name AS patient_name,d.full_name AS doctor_name,a.slot_time
FROM appointments a JOIN patients p USING(patient_id) JOIN doctors d USING(doctor_id)
WHERE a.appointment_day=CURRENT_DATE AND a.status='BOOKED';

CREATE INDEX idx_appointments_day_doctor ON appointments(appointment_day,doctor_id);
EXPLAIN SELECT * FROM appointments WHERE appointment_day=CURRENT_DATE AND doctor_id=1;

CREATE OR REPLACE PROCEDURE pr_refresh_clinic_summary(p_day DATE)
LANGUAGE plpgsql AS $$
BEGIN
 IF p_day IS NULL THEN RAISE EXCEPTION 'Summary date is required'; END IF;
 INSERT INTO clinic_summary(summary_date,booked_count,attended_count,cancelled_count)
 SELECT p_day,
  COUNT(*) FILTER(WHERE status='BOOKED'),
  COUNT(*) FILTER(WHERE status='ATTENDED'),
  COUNT(*) FILTER(WHERE status='CANCELLED')
 FROM appointments WHERE appointment_day=p_day
 ON CONFLICT(summary_date) DO UPDATE SET
 booked_count=EXCLUDED.booked_count,attended_count=EXCLUDED.attended_count,
 cancelled_count=EXCLUDED.cancelled_count;
END; $$;

SELECT * FROM appointments;
SELECT fn_daily_load(1,CURRENT_DATE);
SELECT * FROM v_today_appointments;
CALL pr_refresh_clinic_summary(CURRENT_DATE);
SELECT * FROM clinic_summary;
