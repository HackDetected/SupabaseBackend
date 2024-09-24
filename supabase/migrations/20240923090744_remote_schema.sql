

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "api";


ALTER SCHEMA "api" OWNER TO "postgres";


CREATE SCHEMA IF NOT EXISTS "internal";


ALTER SCHEMA "internal" OWNER TO "postgres";


CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgsodium" WITH SCHEMA "pgsodium";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "internal"."access_level" AS ENUM (
    'read',
    'write'
);


ALTER TYPE "internal"."access_level" OWNER TO "postgres";


CREATE TYPE "internal"."buying_restriction" AS ENUM (
    'purchases',
    'budget',
    'none'
);


ALTER TYPE "internal"."buying_restriction" OWNER TO "postgres";


CREATE TYPE "internal"."product_transport" AS ENUM (
    'shopping_basket',
    'shopping_cart',
    'none'
);


ALTER TYPE "internal"."product_transport" OWNER TO "postgres";


CREATE TYPE "internal"."study_status" AS ENUM (
    'draft',
    'created',
    'ready_for_viewer',
    'ready_for_record',
    'recording',
    'finished_recording',
    'archived'
);


ALTER TYPE "internal"."study_status" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."create_application_version"("version" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$ 
DECLARE
  result bigint;
BEGIN
  if ((SELECT internal.get_is_admin()) is not true) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    INSERT INTO internal.application_versions(application_name, version)
    VALUES ((version->>'application_name')::text, (version->>'version')::text)
    RETURNING id INTO result;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."create_application_version"("version" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."create_product"("product" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_product_category_ids bigint[];
  result bigint;
BEGIN
  accessible_product_category_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_product_category_ids(true) ids));
  if product->>'category_id' IS NULL OR (product->>'category_id')::bigint NOT IN (SELECT unnest(accessible_product_category_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    INSERT INTO internal.products(category_id, custom_id, name, price_tag_text, brand, manufacturer, quantity, note, width, height, depth, price)
    VALUES
    (
      (product->>'category_id')::bigint,
      (product->>'custom_id')::text,
      (product->>'name')::text,
      (product->>'price_tag_text')::text,
      (product->>'brand')::text,
      (product->>'manufacturer')::text,
      (product->>'quantity')::text,
      (product->>'note')::text,
      (product->>'width')::float,
      (product->>'height')::float,
      (product->>'depth')::float,
      (product->>'price')::float
    )
    RETURNING id INTO result;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."create_product"("product" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."create_product_category"("product_category" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  business_unit_ids_to_grant_access bigint[];
  sub_business_unit_ids_without_own bigint[];
  result bigint;
BEGIN
  if product_category->>'parent_id' IS NOT NULL AND (product_category->>'parent_id')::bigint NOT IN (SELECT internal.get_accessible_product_category_ids(true)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    INSERT INTO internal.product_categories(name, parent_id)
    VALUES ((product_category->>'name')::text, (product_category->>'parent_id')::bigint)
    RETURNING id INTO result;

    if product_category->>'accessible_by' IS NOT NULL then
      business_unit_ids_to_grant_access := ARRAY(SELECT (jsonb_array_elements_text((product_category->>'accessible_by')::jsonb))::bigint);
      sub_business_unit_ids_without_own := (SELECT ARRAY(SELECT id FROM internal.get_business_unit_ids_downwards(false)));

      DELETE FROM internal.product_categories_access 
      WHERE business_unit_id IN (SELECT unnest(sub_business_unit_ids_without_own)) 
      AND business_unit_id NOT IN (SELECT unnest(business_unit_ids_to_grant_access)) 
      AND product_category_id = result;

      INSERT INTO internal.product_categories_access(business_unit_id, product_category_id)
      SELECT s.id, result 
      FROM unnest(business_unit_ids_to_grant_access) AS s(id)
      WHERE NOT EXISTS (
        SELECT * 
        FROM internal.product_categories_access 
        WHERE business_unit_id = s.id
          AND product_category_id = result
      )
      AND s.id in (SELECT unnest(sub_business_unit_ids_without_own));
    end if;
  end if;
  RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
END;
$$;


ALTER FUNCTION "api"."create_product_category"("product_category" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."create_sindri_folder"("sindri_folder" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  business_unit_ids_to_grant_access bigint[];
  sub_business_unit_ids_without_own bigint[];
  result bigint;
BEGIN
  if sindri_folder->>'parent_id' IS NOT NULL AND (sindri_folder->>'parent_id')::bigint NOT IN (SELECT internal.get_accessible_sindri_folder_ids(true)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    INSERT INTO internal.sindri_folders(name, parent_id)
    VALUES
    (
      (sindri_folder->>'name')::text,
      (sindri_folder->>'parent_id')::bigint
    )
    RETURNING id INTO result;
    
    if sindri_folder->>'accessible_by' IS NOT NULL then
      business_unit_ids_to_grant_access := ARRAY(SELECT (jsonb_array_elements_text((sindri_folder->>'accessible_by')::jsonb))::bigint);
      sub_business_unit_ids_without_own := (SELECT ARRAY(SELECT id FROM internal.get_business_unit_ids_downwards(false)));

      DELETE FROM internal.sindri_folders_access 
      WHERE business_unit_id IN (SELECT unnest(sub_business_unit_ids_without_own)) 
      AND business_unit_id NOT IN (SELECT unnest(business_unit_ids_to_grant_access)) 
      AND sindri_folder_id = result;

      INSERT INTO internal.sindri_folders_access(business_unit_id, sindri_folder_id)
      SELECT s.id, result 
      FROM unnest(business_unit_ids_to_grant_access) AS s(id)
      WHERE NOT EXISTS (
        SELECT * 
        FROM internal.sindri_folders_access 
        WHERE business_unit_id = s.id
          AND sindri_folder_id = result
      )
      AND s.id IN (SELECT unnest(sub_business_unit_ids_without_own));
    end if;
  end if;
  RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
END;
$$;


ALTER FUNCTION "api"."create_sindri_folder"("sindri_folder" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."create_sindri_save"("sindri_save" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  result bigint;
BEGIN
  if sindri_save->>'folder_id' IS NULL OR (sindri_save->>'folder_id')::bigint NOT IN (SELECT internal.get_accessible_sindri_folder_ids(true)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    INSERT INTO internal.sindri_saves(folder_id, name, content)
    VALUES 
    (
      (sindri_save->>'folder_id')::bigint,
      (sindri_save->>'name')::text,
      (sindri_save->>'content')::text
    )
    RETURNING id INTO result;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."create_sindri_save"("sindri_save" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."create_study"("study" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  business_unit_ids_to_grant_access bigint[];
  sub_business_unit_ids_without_own bigint[];
  monads json;
  monad json;
  scenarios json;
  scenario json;
  i integer;
  result bigint;
BEGIN
  INSERT INTO internal.studies(name, description, number_test_locations, number_participants, status)
  VALUES 
  (
    (study->>'name')::text,
    (study->>'description')::text,
    (study->>'number_test_locations')::bigint,
    (study->>'number_participants')::bigint,
    (study->>'status')::internal.study_status
  )
  RETURNING id INTO result;

  monads := study->'monads';
  if monads IS NOT NULL then
    FOR i IN 0..JSON_ARRAY_LENGTH(monads) - 1 LOOP
      monad := monads->i;
      PERFORM api.create_study_monad(result, monad);  
    END LOOP;
  end if;

  scenarios := study->'scenarios';
  if scenarios IS NOT NULL then
    FOR i IN 0..JSON_ARRAY_LENGTH(scenarios) - 1 LOOP
      scenario := scenarios->i;
      PERFORM api.create_study_scenario(result, scenario);  
    END LOOP;
  end if;

  if study->>'accessible_by' IS NOT NULL then
      business_unit_ids_to_grant_access := ARRAY(SELECT (jsonb_array_elements_text((study->>'accessible_by')::jsonb))::bigint);
      sub_business_unit_ids_without_own := (SELECT ARRAY(SELECT id FROM internal.get_business_unit_ids_downwards(false)));

      DELETE FROM internal.studies_access 
      WHERE business_unit_id IN (SELECT unnest(sub_business_unit_ids_without_own)) 
      AND business_unit_id NOT IN (SELECT unnest(business_unit_ids_to_grant_access)) 
      AND study_id = result;

      INSERT INTO internal.studies_access(business_unit_id, study_id)
      SELECT s.id, result 
      FROM unnest(business_unit_ids_to_grant_access) AS s(id)
      WHERE NOT EXISTS (
        SELECT * 
        FROM internal.studies_access 
        WHERE business_unit_id = s.id
          AND study_id = result
      )
      AND s.id IN (SELECT unnest(sub_business_unit_ids_without_own));
    end if;
  RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
END;
$$;


ALTER FUNCTION "api"."create_study"("study" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."create_study_computer"("computer" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$ 
DECLARE
  result bigint;
BEGIN
  if ((SELECT internal.get_is_admin()) is not true) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    INSERT INTO internal.study_computers(name, description, location, cpu, gpu, identifier, participant_id_min, participant_id_max, study_id)
    VALUES (
      (computer->>'name')::text,
      (computer->>'description')::text,
      (computer->>'location')::text,
      (computer->>'cpu')::text,
      (computer->>'gpu')::text,
      (computer->>'identifier')::text,
      (computer->>'participant_id_min')::bigint,
      (computer->>'participant_id_max')::bigint,
      (computer->>'study_id')::bigint
      )
    RETURNING id INTO result;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."create_study_computer"("computer" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."create_study_environment"("environment" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$ 
DECLARE
  result text;
BEGIN
  if ((SELECT internal.get_is_admin()) is not true) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    INSERT INTO internal.study_environments(name, description, width, height, depth, center_x, center_y, center_z)
    VALUES (
      (environment->>'name')::text,
      (environment->>'description')::text,
      (environment->>'width')::float,
      (environment->>'height')::float,
      (environment->>'depth')::float,
      (environment->>'center_x')::float,
      (environment->>'center_y')::float,
      (environment->>'center_z')::float
      )
    RETURNING name INTO result;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."create_study_environment"("environment" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."create_study_monad"("study_id" bigint, "study_monad" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
  result bigint;
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(true) ids));
  if study_id IS NULL OR study_id NOT IN (SELECT unnest(accessible_study_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    INSERT INTO internal.study_monads(study_id, name, description, participant_goal, scenario_orders, order_in_study, distributions)
    VALUES 
    (
      study_id,
      (study_monad->>'name')::text,
      (study_monad->>'description')::text,
      (study_monad->>'participant_goal')::bigint,
      (study_monad->>'scenario_orders')::json,
      (study_monad->>'order_in_study')::bigint,
      (study_monad->>'distributions')::json
    )
    RETURNING id INTO result;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."create_study_monad"("study_id" bigint, "study_monad" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."create_study_participant"("study_participant" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
  result bigint;
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(true) ids));
  if study_participant->>'study_id' IS NULL OR (study_participant->>'study_id')::bigint NOT IN (SELECT unnest(accessible_study_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  elseif (SELECT COUNT(*) FROM internal.study_participants WHERE custom_id = (study_participant->>'custom_id')::text AND study_id = (study_participant->>'study_id')::bigint) > 0 then
    RETURN(SELECT json_build_object ('response_code', 409, 'message', 'Duplicate.'));
  else
    INSERT INTO internal.study_participants(study_id, custom_id, monad_id, recorded_by, fixation_data_valid, position_data_valid, properties, finished_scenario_ids, finished_task_ids, all_scenarios_finished, all_tasks_finished)
    VALUES 
    (
      (study_participant->>'study_id')::bigint,
      (study_participant->>'custom_id')::text,
      (study_participant->>'monad_id')::bigint,
      (study_participant->>'recorded_by')::bigint,
      (study_participant->>'fixation_data_valid')::boolean,
      (study_participant->>'position_data_valid')::boolean,
      (study_participant->>'properties')::json,
      (study_participant->>'finished_scenario_ids')::json,
      (study_participant->>'finished_task_ids')::json,
      (study_participant->>'all_scenarios_finished')::boolean,
      (study_participant->>'all_tasks_finished')::boolean
    )
    RETURNING id INTO result;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."create_study_participant"("study_participant" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."create_study_scenario"("study_id" bigint, "study_scenario" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
  tasks json;
  task json;
  i integer;
  result bigint;
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(true) ids));
  if study_id IS NULL OR study_id NOT IN (SELECT unnest(accessible_study_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    INSERT INTO internal.study_scenarios(study_id, name, description, optional, environment_name, order_in_study)
    VALUES 
    (
      study_id,
      (study_scenario->>'name')::text,
      (study_scenario->>'description')::text,
      (study_scenario->>'optional')::boolean,
      (study_scenario->'environment')->>'name'::text,
      (study_scenario->>'order_in_study')::bigint
    )
    RETURNING id INTO result;
    tasks := study_scenario->'tasks';
    if tasks IS NOT NULL then
      FOR i IN 0..JSON_ARRAY_LENGTH(tasks) - 1 LOOP
        task := tasks->i;
        PERFORM api.create_study_task(study_id, result, task);  
      END LOOP;
    end if;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."create_study_scenario"("study_id" bigint, "study_scenario" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."create_study_task"("study_id" bigint, "scenario_id" bigint, "study_task" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
  result bigint;
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(true) ids));
  if study_id IS NULL OR study_id NOT IN (SELECT unnest(accessible_study_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    INSERT INTO internal.study_tasks(study_id, scenario_id, name, description, task_text, start_position_x, start_position_y, start_position_z, product_transport, buying_restriction, buying_limit, blind_limit, teleport_range, set_time_stamp_button, order_in_scenario, start_rotation, optional)
    VALUES 
    (
      study_id,
      scenario_id,
      (study_task->>'name')::text,
      (study_task->>'description')::text,
      (study_task->>'task_text')::text,
      (study_task->>'start_position_x')::float,
      (study_task->>'start_position_y')::float,
      (study_task->>'start_position_z')::float,
      (study_task->>'product_transport')::internal.product_transport,
      (study_task->>'buying_restriction')::internal.buying_restriction,
      (study_task->>'buying_limit')::float,
      (study_task->>'blind_limit')::boolean,
      (study_task->>'teleport_range')::float,
      (study_task->>'set_time_stamp_button')::boolean,
      (study_task->>'order_in_scenario')::bigint,
      (study_task->>'start_rotation')::float,
      (study_task->>'optional')::boolean
    )
    RETURNING id INTO result;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."create_study_task"("study_id" bigint, "scenario_id" bigint, "study_task" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."delete_application_version"("id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  if ((SELECT internal.get_is_admin()) is not true) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    DELETE FROM internal.application_versions av WHERE av.id = delete_application_version.id;
    RETURN(SELECT json_build_object ('response_code', 200, 'message', 'OK'));
  end if;
END;
$$;


ALTER FUNCTION "api"."delete_application_version"("id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."delete_product"("id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_product_category_ids bigint[];
BEGIN
  accessible_product_category_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_product_category_ids(true) ids));
  if (SELECT p.category_id FROM internal.products p WHERE p.id = delete_product.id) NOT IN (SELECT unnest(accessible_product_category_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    DELETE FROM internal.products p WHERE p.id = delete_product.id;
    RETURN(SELECT json_build_object ('response_code', 200, 'message', 'OK'));
  end if;
END;
$$;


ALTER FUNCTION "api"."delete_product"("id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."delete_product_category"("id" bigint, "move_products_to_id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_product_category_ids bigint[];
  child_categories bigint[];
BEGIN
  accessible_product_category_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_product_category_ids(true) ids));
  child_categories := (SELECT ARRAY(SELECT ids.id FROM internal.get_product_category_ids_downwards(delete_product_category.id, false, true, accessible_product_category_ids) ids));
  if (delete_product_category.id IS NULL OR delete_product_category.id NOT IN (SELECT unnest(accessible_product_category_ids))) OR 
      (move_products_to_id IS NOT NULL AND move_products_to_id NOT IN (SELECT unnest(accessible_product_category_ids))) OR
      (NOT (child_categories <@ accessible_product_category_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    if move_products_to_id IS NOT NULL then
      UPDATE internal.products SET category_id = move_products_to_id WHERE category_id = delete_product_category.id;
      UPDATE internal.product_categories SET parent_id = move_products_to_id WHERE parent_id = delete_product_category.id;
    end if;
    DELETE FROM internal.product_categories pc WHERE pc.id = delete_product_category.id AND pc.id IN (SELECT unnest(accessible_product_category_ids));
    RETURN(SELECT json_build_object ('response_code', 200, 'message', 'OK'));
  end if;
END;
$$;


ALTER FUNCTION "api"."delete_product_category"("id" bigint, "move_products_to_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."delete_sindri_folder"("id" bigint, "move_saves_to_id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_sindri_folder_ids bigint[];
  child_folders bigint[];
BEGIN
  accessible_sindri_folder_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_sindri_folder_ids(true) ids));
  child_folders := (SELECT ARRAY(SELECT ids.id FROM internal.get_sindri_folder_ids_downwards(delete_sindri_folder.id, false, true, accessible_sindri_folder_ids) ids));
  if (delete_sindri_folder.id IS NULL OR delete_sindri_folder.id NOT IN (SELECT unnest(accessible_sindri_folder_ids))) OR 
      (move_saves_to_id IS NOT NULL AND move_saves_to_id NOT IN (SELECT unnest(accessible_sindri_folder_ids))) OR
      (NOT (child_folders <@ accessible_sindri_folder_ids))then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    if move_saves_to_id IS NOT NULL then
      UPDATE internal.sindri_saves SET folder_id = move_saves_to_id WHERE folder_id = delete_sindri_folder.id;
      UPDATE internal.sindri_folders SET parent_id = move_saves_to_id WHERE parent_id = delete_sindri_folder.id;
    end if;
    DELETE FROM internal.sindri_folders sf WHERE sf.id = delete_sindri_folder.id AND sf.id IN (SELECT unnest(accessible_sindri_folder_ids));
    RETURN(SELECT json_build_object ('response_code', 200, 'message', 'OK'));
  end if;
END;
$$;


ALTER FUNCTION "api"."delete_sindri_folder"("id" bigint, "move_saves_to_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."delete_sindri_save"("id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_sindri_folder_ids bigint[];
BEGIN
  accessible_sindri_folder_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_sindri_folder_ids(true) ids));
  if (SELECT ss.folder_id FROM internal.sindri_saves ss WHERE ss.id = delete_sindri_save.id) NOT IN (SELECT unnest(accessible_sindri_folder_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    DELETE FROM internal.sindri_saves ss WHERE ss.id = delete_sindri_save.id;
    RETURN(SELECT json_build_object ('response_code', 200, 'message', 'OK'));
  end if;
END;
$$;


ALTER FUNCTION "api"."delete_sindri_save"("id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."delete_study"("id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(true) ids));
  if id NOT IN (SELECT unnest(accessible_study_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    DELETE FROM internal.studies s WHERE s.id = delete_study.id;
    RETURN(SELECT json_build_object ('response_code', 200, 'message', 'OK'));
  end if;
END;
$$;


ALTER FUNCTION "api"."delete_study"("id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."delete_study_computer"("id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  if ((SELECT internal.get_is_admin()) is not true) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    DELETE FROM internal.study_computers comp WHERE comp.id = delete_study_computer.id;
    RETURN(SELECT json_build_object ('response_code', 200, 'message', 'OK'));
  end if;
END;
$$;


ALTER FUNCTION "api"."delete_study_computer"("id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."delete_study_environment"("name" "text") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  if ((SELECT internal.get_is_admin()) is not true) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    DELETE FROM internal.study_environments env WHERE env.name = delete_study_environment.name;
    RETURN(SELECT json_build_object ('response_code', 200, 'message', 'OK'));
  end if;
END;
$$;


ALTER FUNCTION "api"."delete_study_environment"("name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."delete_study_monad"("id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(true) ids));
  if (SELECT sm.study_id FROM internal.study_monads sm WHERE sm.id = delete_study_monad.id) NOT IN (SELECT unnest(accessible_study_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    DELETE FROM internal.study_monads sm WHERE sm.id = delete_study_monad.id;
    RETURN(SELECT json_build_object ('response_code', 200, 'message', 'OK'));
  end if;
END;
$$;


ALTER FUNCTION "api"."delete_study_monad"("id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."delete_study_participant"("id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(true) ids));
  if (SELECT sp.study_id FROM internal.study_participants sp WHERE sp.id = delete_study_participant.id) NOT IN (SELECT unnest(accessible_study_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    DELETE FROM internal.study_participants sp WHERE sp.id = delete_study_participant.id;
    RETURN(SELECT json_build_object ('response_code', 200, 'message', 'OK'));
  end if;
END;
$$;


ALTER FUNCTION "api"."delete_study_participant"("id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."delete_study_scenario"("id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(true) ids));
  if (SELECT ss.study_id FROM internal.study_scenarios ss WHERE ss.id = delete_study_scenario.id) NOT IN (SELECT unnest(accessible_study_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    DELETE FROM internal.study_scenarios ss WHERE ss.id = delete_study_scenario.id;
    RETURN(SELECT json_build_object ('response_code', 200, 'message', 'OK'));
  end if;
END;
$$;


ALTER FUNCTION "api"."delete_study_scenario"("id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."delete_study_task"("id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(true) ids));
  if (SELECT st.study_id FROM internal.study_tasks st WHERE st.id = delete_study_task.id) NOT IN (SELECT unnest(accessible_study_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    DELETE FROM internal.study_tasks st WHERE st.id = delete_study_task.id;
    RETURN(SELECT json_build_object ('response_code', 200, 'message', 'OK'));
  end if;
END;
$$;


ALTER FUNCTION "api"."delete_study_task"("id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_all_study_monads"() RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT id FROM internal.get_accessible_study_ids(false)));
  RETURN(SELECT array_to_json(array_agg(row_to_json(data)))
  FROM(
    SELECT sm.*
    FROM internal.study_monads sm
    WHERE sm.study_id IN (SELECT unnest(accessible_study_ids))
  )data);
END;
$$;


ALTER FUNCTION "api"."get_all_study_monads"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_all_study_scenarios"() RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT id FROM internal.get_accessible_study_ids(false)));
  RETURN(SELECT array_to_json(array_agg(row_to_json(data)))
  FROM(
    SELECT ss.*,
    (CASE
      WHEN (ss.environment_name IS NOT NULL) THEN (SELECT api.get_study_environment(ss.environment_name))
      ELSE null
    END) AS environment,
    (SELECT api.get_study_tasks(ss.id)) as tasks
    FROM internal.study_scenarios ss
    WHERE ss.study_id IN (SELECT unnest(accessible_study_ids))
  )data);
END;
$$;


ALTER FUNCTION "api"."get_all_study_scenarios"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_all_study_tasks"() RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT id FROM internal.get_accessible_study_ids(false)));
  RETURN(SELECT array_to_json(array_agg(row_to_json(data)))
  FROM(
    SELECT st.*
    FROM internal.study_tasks st
    WHERE st.study_id IN (SELECT unnest(accessible_study_ids))
  )data);
END;
$$;


ALTER FUNCTION "api"."get_all_study_tasks"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_application"("name" "text") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN(SELECT row_to_json(data)
  FROM(
    SELECT a.name, 
    (SELECT row_to_json(av) FROM internal.application_versions av WHERE id = a.beta_version_id) as beta_version,
    (SELECT row_to_json(av) FROM internal.application_versions av WHERE id = a.release_version_id) as release_version
    FROM internal.applications a
    WHERE a.name = get_application.name
  )data);
END;
$$;


ALTER FUNCTION "api"."get_application"("name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_application_version"("id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN(SELECT row_to_json(data)
  FROM(
    SELECT *
    FROM internal.application_versions av
    WHERE av.id = get_application_version.id
  )data);
END;
$$;


ALTER FUNCTION "api"."get_application_version"("id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_application_versions"("application_name" "text") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN(SELECT array_to_json(array_agg(row_to_json(data)))
  FROM(
    SELECT * FROM internal.application_versions av WHERE av.application_name = get_application_versions.application_name
  )data);
END;
$$;


ALTER FUNCTION "api"."get_application_versions"("application_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_business_units"() RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN(SELECT array_to_json(array_agg(row_to_json(data)))
  FROM(
    SELECT * FROM internal.business_units WHERE id in (SELECT internal.get_business_unit_ids_downwards(true))
  )data);
END;
$$;


ALTER FUNCTION "api"."get_business_units"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_nearest_common_ancestor"("category_ids" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
    paths jsonb[];
    min_length bigint;
    i bigint;
    j bigint;
    current_element bigint;
    all_contain BOOLEAN;
    accessible_product_category_ids bigint[];
BEGIN
    accessible_product_category_ids := (SELECT ARRAY(SELECT id FROM internal.get_accessible_product_category_ids(false)));
    SELECT ARRAY_AGG(to_jsonb(internal.get_category_id_parent_path(id::bigint, accessible_product_category_ids, false))) INTO paths
    FROM jsonb_array_elements_text(category_ids::jsonb) as id;

    min_length := array_length(paths, 1);
    FOR i IN 1..array_length(paths, 1) LOOP
        min_length := LEAST(min_length, jsonb_array_length(paths[i]));
    END LOOP;

    FOR i IN REVERSE (min_length-1)..0 LOOP
        current_element := (paths[1]->>i)::bigint;
        all_contain := TRUE;       
        FOR j IN 2..array_length(paths, 1) LOOP
            IF NOT EXISTS (
                SELECT 1
                FROM jsonb_array_elements_text(paths[j]) AS elem
                WHERE (elem)::bigint = current_element
            ) THEN
                all_contain := FALSE;
                EXIT;
            END IF;
        END LOOP;
        IF all_contain THEN
            RETURN (SELECT api.get_product_category(current_element));
        END IF;
    END LOOP;
    RETURN(SELECT json_build_object ('response_code', 404, 'id', null));
END;
$$;


ALTER FUNCTION "api"."get_nearest_common_ancestor"("category_ids" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_own_business_unit"() RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN(SELECT row_to_json(data)
  FROM(
    SELECT * FROM internal.business_units WHERE id =
    (SELECT internal.get_own_business_unit_id())
  )data);
END;
$$;


ALTER FUNCTION "api"."get_own_business_unit"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_product"("id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_product_category_ids bigint[];
BEGIN
  accessible_product_category_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_product_category_ids(false) ids));
  RETURN(SELECT row_to_json(data)
  FROM(
    SELECT p.*,
    (SELECT internal.get_product_category_path(p.category_id, accessible_product_category_ids)) AS category_path,
    (SELECT access_level FROM internal.product_categories_access WHERE product_category_id = p.category_id AND business_unit_id = (SELECT internal.get_own_business_unit_id())) AS access_level
    FROM internal.products p
    WHERE p.id = get_product.id
    AND category_id IN (SELECT unnest(accessible_product_category_ids))
  )data);
END;
$$;


ALTER FUNCTION "api"."get_product"("id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_product_categories"("filters" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_product_category_ids bigint[];
BEGIN
  accessible_product_category_ids := (SELECT ARRAY(SELECT id FROM internal.get_accessible_product_category_ids(false)));
  RETURN(SELECT array_to_json(array_agg(row_to_json(data)))
  FROM(
    SELECT pc.id, pc.name,
    CASE
      WHEN (pc.parent_id IN (SELECT unnest(accessible_product_category_ids))) THEN pc.parent_id
      ELSE 0
    END AS parent_id,
    (SELECT ARRAY(SELECT ids.id FROM internal.get_product_category_ids_downwards(pc.id, false, false, accessible_product_category_ids) ids)) AS children_ids,
    (SELECT ARRAY(SELECT pcc.id FROM internal.product_categories pcc WHERE parent_id = pc.id AND pcc.id IN (SELECT unnest(accessible_product_category_ids)))) AS direct_children_ids,
    (SELECT ARRAY(SELECT p.id FROM internal.products p WHERE p.category_id in (SELECT internal.get_product_category_ids_downwards(pc.id, true, false, accessible_product_category_ids)))) AS product_ids,
    (SELECT ARRAY(SELECT p.id FROM internal.products p WHERE p.category_id = pc.id)) AS direct_product_ids,
    (SELECT internal.get_product_category_path (pc.id, accessible_product_category_ids)) AS category_path,
    (SELECT ARRAY(SELECT business_unit_id FROM internal.product_categories_access WHERE product_category_id = pc.id AND business_unit_id IN (SELECT internal.get_business_unit_ids_downwards(false)))) AS accessible_by,
    (SELECT access_level FROM internal.product_categories_access WHERE product_category_id = pc.id AND business_unit_id = (SELECT internal.get_own_business_unit_id())) AS access_level
    FROM internal.product_categories pc
    WHERE 
    (
      (id IN (SELECT unnest(accessible_product_category_ids)))
    )
    AND
    (
      (filters->>'parent_id' IS NULL)
      OR
      ((filters->>'parent_id')::bigint = 0 AND (parent_id is null OR parent_id NOT IN (SELECT unnest(accessible_product_category_ids))))
      OR
      ((filters->>'parent_id')::bigint = parent_id)
    )
    AND
    (
      (filters->>'name_type' IS NULL)
      OR
      ((filters->>'name_type')::text = 'contain' AND filters->>'name_value' IS NOT NULL AND lower(name) ILIKE '%' || lower((filters->>'name_value')::text) || '%')
      OR
      ((filters->>'name_type')::text = 'not_contain' AND filters->>'name_value' IS NOT NULL AND lower(name) NOT ILIKE '%' || lower((filters->>'name_value')::text) || '%')
      OR
      ((filters->>'name_type')::text = 'equals' AND filters->>'name_value' IS NOT NULL AND lower(name) = lower((filters->>'name_value')::text))
    )
    AND
    (
      (filters->>'search_term' IS NULL)
      OR
      (
        (id::text ILIKE '%' || lower((filters->>'search_term')::text) || '%') OR
        (lower(name) ILIKE '%' || lower((filters->>'search_term')::text) || '%')
      )
    )
  )data);
END;
$$;


ALTER FUNCTION "api"."get_product_categories"("filters" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_product_category"("id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_product_category_ids bigint[];
BEGIN
  accessible_product_category_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_product_category_ids(false) ids));
  RETURN(SELECT row_to_json(data)
  FROM(
    SELECT pc.id, pc.name,
    CASE
      WHEN (pc.parent_id IN (SELECT unnest(accessible_product_category_ids))) THEN pc.parent_id
      ELSE 0
    END AS parent_id,
    (SELECT ARRAY(SELECT ids.id FROM internal.get_product_category_ids_downwards(pc.id, false, false, accessible_product_category_ids) ids)) AS children_ids,
    (SELECT ARRAY(SELECT pcc.id FROM internal.product_categories pcc WHERE parent_id = pc.id AND pcc.id IN (SELECT unnest(accessible_product_category_ids)))) AS direct_children_ids,
    (SELECT ARRAY(SELECT p.id FROM internal.products p WHERE p.category_id in (SELECT internal.get_product_category_ids_downwards(pc.id, true, false, accessible_product_category_ids)))) AS product_ids,
    (SELECT ARRAY(SELECT p.id FROM internal.products p WHERE p.category_id = pc.id)) AS direct_product_ids,
    (SELECT internal.get_product_category_path (pc.id, accessible_product_category_ids)) AS category_path,
    (SELECT ARRAY(SELECT business_unit_id FROM internal.product_categories_access WHERE product_category_id = pc.id AND business_unit_id IN (SELECT internal.get_business_unit_ids_downwards(false)))) AS accessible_by,
    (SELECT access_level FROM internal.product_categories_access WHERE product_category_id = pc.id AND business_unit_id = (SELECT internal.get_own_business_unit_id())) AS access_level
    FROM internal.product_categories pc
    WHERE pc.id = get_product_category.id
    AND pc.id IN (SELECT unnest(accessible_product_category_ids))
  )data);
END;
$$;


ALTER FUNCTION "api"."get_product_category"("id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_products"("filters" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_product_category_ids bigint[];
BEGIN
  accessible_product_category_ids := (SELECT ARRAY(SELECT id FROM internal.get_accessible_product_category_ids(false)));
  RETURN(SELECT array_to_json(array_agg(row_to_json(data)))
  FROM(
    SELECT p.*,
    (SELECT internal.get_product_category_path(p.category_id, accessible_product_category_ids)) AS category_path,
    (SELECT access_level FROM internal.product_categories_access WHERE product_category_id = p.category_id AND business_unit_id = (SELECT internal.get_own_business_unit_id())) AS access_level
    FROM internal.products p
    WHERE 
    (
      (category_id IN (SELECT unnest(accessible_product_category_ids)))
    )
    AND
    (
      (filters->>'category_id_type' IS NULL)
      OR
      ((filters->>'category_id_type')::text = 'non_recursive' AND (filters->>'category_id_value')::bigint IS NOT NULL AND category_id = (filters->>'category_id_value')::bigint)
      OR
      ((filters->>'category_id_type')::text = 'recursive' AND (filters->>'category_id_value')::bigint IS NOT NULL AND category_id IN (SELECT internal.get_product_category_ids_downwards((filters->>'category_id_value')::bigint, true, false, accessible_product_category_ids)))
    )
    AND
    (
      (filters->>'id_type' IS NULL)
      OR
      ((filters->>'id_type')::text = 'smaller' AND (filters->>'id_value_low')::bigint IS NOT NULL AND id < (filters->>'id_value_low')::bigint)
      OR
      ((filters->>'id_type')::text = 'greater' AND (filters->>'id_value_low')::bigint IS NOT NULL AND id > (filters->>'id_value_low')::bigint)
      OR
      ((filters->>'id_type')::text = 'in_between' AND (filters->>'id_value_low')::bigint IS NOT NULL AND (filters->>'id_value_high')::bigint IS NOT NULL AND id > (filters->>'id_value_low')::bigint AND id < (filters->>'id_value_high')::bigint)
      OR
      ((filters->>'id_type')::text = 'equals' AND (filters->>'id_value_low')::bigint IS NOT NULL AND id = (filters->>'id_value_low')::bigint)
    )
    AND
    (
      (filters->>'custom_id_type' IS NULL)
      OR
      ((filters->>'custom_id_type')::text = 'contain' AND filters->>'custom_id_value' IS NOT NULL AND lower(custom_id) ILIKE '%' || lower((filters->>'custom_id_value')::text) || '%')
      OR
      ((filters->>'custom_id_type')::text = 'not_contain' AND filters->>'custom_id_value' IS NOT NULL AND lower(custom_id) NOT ILIKE '%' || lower((filters->>'custom_id_value')::text) || '%')
      OR
      ((filters->>'custom_id_type')::text = 'equals' AND filters->>'custom_id_value' IS NOT NULL AND lower(custom_id) = lower((filters->>'custom_id_value')::text))
    )
    AND
    (
      (filters->>'name_type' IS NULL)
      OR
      ((filters->>'name_type')::text = 'contain' AND filters->>'name_value' IS NOT NULL AND lower(name) ILIKE '%' || lower((filters->>'name_value')::text) || '%')
      OR
      ((filters->>'name_type')::text = 'not_contain' AND filters->>'name_value' IS NOT NULL AND lower(name) NOT ILIKE '%' || lower((filters->>'name_value')::text) || '%')
      OR
      ((filters->>'name_type')::text = 'equals' AND filters->>'name_value' IS NOT NULL AND lower(name) = lower((filters->>'name_value')::text))
    )
    AND
    (
      (filters->>'price_tag_text_type' IS NULL)
      OR
      ((filters->>'price_tag_text_type')::text = 'contain' AND filters->>'price_tag_text_value' IS NOT NULL AND lower(price_tag_text) ILIKE '%' || lower((filters->>'price_tag_text_value')::text) || '%')
      OR
      ((filters->>'price_tag_text_type')::text = 'not_contain' AND filters->>'price_tag_text_value' IS NOT NULL AND lower(price_tag_text) NOT ILIKE '%' || lower((filters->>'price_tag_text_value')::text) || '%')
      OR
      ((filters->>'price_tag_text_type')::text = 'equals' AND filters->>'price_tag_text_value' IS NOT NULL AND lower(price_tag_text) = lower((filters->>'price_tag_text_value')::text))
    )
    AND
    (
      (filters->>'brand_type' IS NULL)
      OR
      ((filters->>'brand_type')::text = 'contain' AND filters->>'brand_value' IS NOT NULL AND lower(brand) ILIKE '%' || lower((filters->>'brand_value')::text) || '%')
      OR
      ((filters->>'brand_type')::text = 'not_contain' AND filters->>'brand_value' IS NOT NULL AND lower(brand) NOT ILIKE '%' || lower((filters->>'brand_value')::text) || '%')
      OR
      ((filters->>'brand_type')::text = 'equals' AND filters->>'brand_value' IS NOT NULL AND lower(brand) = lower((filters->>'brand_value')::text))
    )
    AND
    (
      (filters->>'manufacturer_type' IS NULL)
      OR
      ((filters->>'manufacturer_type')::text = 'contain' AND filters->>'manufacturer_value' IS NOT NULL AND lower(manufacturer) ILIKE '%' || lower((filters->>'manufacturer_value')::text) || '%')
      OR
      ((filters->>'manufacturer_type')::text = 'not_contain' AND filters->>'manufacturer_value' IS NOT NULL AND lower(manufacturer) NOT ILIKE '%' || lower((filters->>'manufacturer_value')::text) || '%')
      OR
      ((filters->>'manufacturer_type')::text = 'equals' AND filters->>'manufacturer_value' IS NOT NULL AND lower(manufacturer) = lower((filters->>'manufacturer_value')::text))
    )
    AND
    (
      (filters->>'quantity_type' IS NULL)
      OR
      ((filters->>'quantity_type')::text = 'contain' AND filters->>'quantity_value' IS NOT NULL AND lower(quantity) ILIKE '%' || lower((filters->>'quantity_value')::text) || '%')
      OR
      ((filters->>'quantity_type')::text = 'not_contain' AND filters->>'quantity_value' IS NOT NULL AND lower(quantity) NOT ILIKE '%' || lower((filters->>'quantity_value')::text) || '%')
      OR
      ((filters->>'quantity_type')::text = 'equals' AND filters->>'quantity_value' IS NOT NULL AND lower(quantity) = lower((filters->>'quantity_value')::text))
    )
    AND
    (
      (filters->>'price_type' IS NULL)
      OR
      ((filters->>'price_type')::text = 'smaller' AND (filters->>'price_value_low')::float IS NOT NULL AND price < (filters->>'price_value_low')::float)
      OR
      ((filters->>'price_type')::text = 'greater' AND (filters->>'price_value_low')::float IS NOT NULL AND price > (filters->>'price_value_low')::float)
      OR
      ((filters->>'price_type')::text = 'in_between' AND (filters->>'price_value_low')::float IS NOT NULL AND (filters->>'price_value_high')::float IS NOT NULL AND price > (filters->>'price_value_low')::float AND price < (filters->>'price_value_high')::float)
      OR
      ((filters->>'price_type')::text = 'equals' AND (filters->>'price_value_low')::float IS NOT NULL AND price = (filters->>'price_value_low')::float)
    )
    AND
    (
      (filters->>'search_term' IS NULL)
      OR
      (
        (id::text ILIKE '%' || lower((filters->>'search_term')::text) || '%') OR
        (lower(name) ILIKE '%' || lower((filters->>'search_term')::text) || '%') OR
        (lower(brand) ILIKE '%' || lower((filters->>'search_term')::text) || '%') OR
        (lower(manufacturer) ILIKE '%' || lower((filters->>'search_term')::text) || '%') OR
        (lower(price_tag_text) ILIKE '%' || lower((filters->>'search_term')::text) || '%') OR
        (lower(quantity) ILIKE '%' || lower((filters->>'search_term')::text) || '%') OR
        (lower(custom_id) ILIKE '%' || lower((filters->>'search_term')::text) || '%')
      )
    )
  )data);
END;
$$;


ALTER FUNCTION "api"."get_products"("filters" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_products_by_ids"("ids" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_product_category_ids bigint[];
BEGIN
  accessible_product_category_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_product_category_ids(false) ids));
  RETURN(SELECT array_to_json(array_agg(row_to_json(data)))
  FROM(
    SELECT p.*,
    (SELECT internal.get_product_category_path(p.category_id, accessible_product_category_ids)) AS category_path,
    (SELECT access_level FROM internal.product_categories_access WHERE product_category_id = p.category_id AND business_unit_id = (SELECT internal.get_own_business_unit_id())) AS access_level
    FROM internal.products p
    WHERE 
    (
      id IN (SELECT (jsonb_array_elements_text(ids::jsonb))::bigint)
      AND
      category_id IN (SELECT unnest(accessible_product_category_ids))
    )
  )data);
END;
$$;


ALTER FUNCTION "api"."get_products_by_ids"("ids" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_sindri_folder"("id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_sindri_folder_ids bigint[];
BEGIN
  accessible_sindri_folder_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_sindri_folder_ids(false) ids));
  RETURN(SELECT row_to_json(data)
  FROM(
    SELECT sf.id, sf.name,
    CASE
      WHEN (sf.parent_id IN (SELECT unnest(accessible_sindri_folder_ids))) THEN sf.parent_id
      ELSE 0
    END AS parent_id,
    (SELECT ARRAY(SELECT ids.id FROM internal.get_sindri_folder_ids_downwards(sf.id, false, false, accessible_sindri_folder_ids) ids)) AS children_ids,
    (SELECT ARRAY(SELECT sff.id FROM internal.sindri_folders sff WHERE parent_id = sf.id AND sff.id IN (SELECT unnest(accessible_sindri_folder_ids)))) AS direct_children_ids,
    (SELECT ARRAY(SELECT ss.id FROM internal.sindri_saves ss WHERE ss.folder_id in (SELECT internal.get_sindri_folder_ids_downwards(sf.id, true, false, accessible_sindri_folder_ids)))) AS save_ids,
    (SELECT ARRAY(SELECT ss.id FROM internal.sindri_saves ss WHERE ss.folder_id = sf.id)) AS direct_save_ids,
    (SELECT internal.get_sindri_folder_path (sf.id, accessible_sindri_folder_ids)) AS folder_path,
    (SELECT ARRAY(SELECT business_unit_id FROM internal.sindri_folders_access WHERE sindri_folder_id = sf.id AND business_unit_id IN (SELECT internal.get_business_unit_ids_downwards(false)))) AS accessible_by,
    (SELECT access_level FROM internal.sindri_folders_access WHERE sindri_folder_id = sf.id AND business_unit_id = (SELECT internal.get_own_business_unit_id())) AS access_level
    FROM internal.sindri_folders sf
    WHERE sf.id = get_sindri_folder.id
    AND sf.id IN (SELECT unnest(accessible_sindri_folder_ids))
  )data);
END;
$$;


ALTER FUNCTION "api"."get_sindri_folder"("id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_sindri_folders"("filters" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_sindri_folder_ids bigint[];
BEGIN
  accessible_sindri_folder_ids := (SELECT ARRAY(SELECT id FROM internal.get_accessible_sindri_folder_ids(false)));
  RETURN(SELECT array_to_json(array_agg(row_to_json(data)))
  FROM(
    SELECT sf.id, sf.name,
    CASE
      WHEN (sf.parent_id IN (SELECT unnest(accessible_sindri_folder_ids))) THEN sf.parent_id
      ELSE 0
    END AS parent_id,
    (SELECT ARRAY(SELECT ids.id FROM internal.get_sindri_folder_ids_downwards(sf.id, false, false, accessible_sindri_folder_ids) ids)) AS children_ids,
    (SELECT ARRAY(SELECT sff.id FROM internal.sindri_folders sff WHERE parent_id = sf.id AND sff.id IN (SELECT unnest(accessible_sindri_folder_ids)))) AS direct_children_ids,
    (SELECT ARRAY(SELECT ss.id FROM internal.sindri_saves ss WHERE ss.folder_id in (SELECT internal.get_sindri_folder_ids_downwards(sf.id, true, false, accessible_sindri_folder_ids)))) AS save_ids,
    (SELECT ARRAY(SELECT ss.id FROM internal.sindri_saves ss WHERE ss.folder_id = sf.id)) AS direct_save_ids,
    (SELECT internal.get_sindri_folder_path (sf.id, accessible_sindri_folder_ids)) AS folder_path,
    (SELECT ARRAY(SELECT business_unit_id FROM internal.sindri_folders_access WHERE sindri_folder_id = sf.id AND business_unit_id IN (SELECT internal.get_business_unit_ids_downwards(false)))) AS accessible_by,
    (SELECT access_level FROM internal.sindri_folders_access WHERE sindri_folder_id = sf.id AND business_unit_id = (SELECT internal.get_own_business_unit_id())) AS access_level
    FROM internal.sindri_folders sf
    WHERE 
    (
      (id IN (SELECT unnest(accessible_sindri_folder_ids)))
    )
    AND
    (
      (filters->>'parent_id' IS NULL)
      OR
      ((filters->>'parent_id')::bigint = 0 AND parent_id is null)
      OR
      ((filters->>'parent_id')::bigint = parent_id)
    )
    AND
    (
      (filters->>'name_type' IS NULL)
      OR
      ((filters->>'name_type')::text = 'contain' AND filters->>'name_value' IS NOT NULL AND lower(name) ILIKE '%' || lower((filters->>'name_value')::text) || '%')
      OR
      ((filters->>'name_type')::text = 'not_contain' AND filters->>'name_value' IS NOT NULL AND lower(name) NOT ILIKE '%' || lower((filters->>'name_value')::text) || '%')
      OR
      ((filters->>'name_type')::text = 'equals' AND filters->>'name_value' IS NOT NULL AND lower(name) = lower((filters->>'name_value')::text))
    )
    AND
    (
      (filters->>'search_term' IS NULL)
      OR
      (
        (id::text ILIKE '%' || lower((filters->>'search_term')::text) || '%') OR
        (lower(name) ILIKE '%' || lower((filters->>'search_term')::text) || '%')
      )
    )
  )data);
END;
$$;


ALTER FUNCTION "api"."get_sindri_folders"("filters" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_sindri_save"("id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_sindri_folder_ids bigint[];
BEGIN
  accessible_sindri_folder_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_sindri_folder_ids(false) ids));
  RETURN(SELECT row_to_json(data)
  FROM(
    SELECT ss.*,
    (SELECT internal.get_sindri_folder_path(ss.folder_id, accessible_sindri_folder_ids)) AS folder_path,
    (SELECT access_level FROM internal.sindri_folders_access WHERE sindri_folder_id = ss.folder_id AND business_unit_id = (SELECT internal.get_own_business_unit_id())) AS access_level
    FROM internal.sindri_saves ss
    WHERE ss.id = get_sindri_save.id
    AND folder_id IN (SELECT unnest(accessible_sindri_folder_ids))
  )data);
END;
$$;


ALTER FUNCTION "api"."get_sindri_save"("id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_sindri_saves"("filters" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_sindri_folder_ids bigint[];
BEGIN
  accessible_sindri_folder_ids := (SELECT ARRAY(SELECT id FROM internal.get_accessible_sindri_folder_ids(false)));
  RETURN(SELECT array_to_json(array_agg(row_to_json(data)))
  FROM(
    SELECT ss.id, ss.folder_id, ss.name, ss.created_at, ss.updated_at,
    (SELECT internal.get_sindri_folder_path(ss.folder_id, accessible_sindri_folder_ids)) AS folder_path,
    (SELECT access_level FROM internal.sindri_folders_access WHERE sindri_folder_id = ss.folder_id AND business_unit_id = (SELECT internal.get_own_business_unit_id())) AS access_level
    FROM internal.sindri_saves ss
    WHERE 
    (
      (folder_id IN (SELECT unnest(accessible_sindri_folder_ids)) )
    )
    AND
    (
      (filters->>'folder_id_type' IS NULL)
      OR
      ((filters->>'folder_id_type')::text = 'non_recursive' AND (filters->>'folder_id_value')::bigint IS NOT NULL AND folder_id = (filters->>'folder_id_value')::bigint)
      OR
      ((filters->>'folder_id_type')::text = 'recursive' AND (filters->>'folder_id_value')::bigint IS NOT NULL AND folder_id IN (SELECT internal.get_sindri_folder_ids_downwards((filters->>'folder_id_value')::bigint, true, false, accessible_sindri_folder_ids)))
    )
    AND
    (
      (filters->>'id_type' IS NULL)
      OR
      ((filters->>'id_type')::text = 'smaller' AND (filters->>'id_value_low')::bigint IS NOT NULL AND id < (filters->>'id_value_low')::bigint)
      OR
      ((filters->>'id_type')::text = 'greater' AND (filters->>'id_value_low')::bigint IS NOT NULL AND id > (filters->>'id_value_low')::bigint)
      OR
      ((filters->>'id_type')::text = 'in_between' AND (filters->>'id_value_low')::bigint IS NOT NULL AND (filters->>'id_value_high')::bigint IS NOT NULL AND id > (filters->>'id_value_low')::bigint AND id < (filters->>'id_value_high')::bigint)
      OR
      ((filters->>'id_type')::text = 'equals' AND (filters->>'id_value_low')::bigint IS NOT NULL AND id = (filters->>'id_value_low')::bigint)
    )
    AND
    (
      (filters->>'name_type' IS NULL)
      OR
      ((filters->>'name_type')::text = 'contain' AND filters->>'name_value' IS NOT NULL AND lower(name) ILIKE '%' || lower((filters->>'name_value')::text) || '%')
      OR
      ((filters->>'name_type')::text = 'not_contain' AND filters->>'name_value' IS NOT NULL AND lower(name) NOT ILIKE '%' || lower((filters->>'name_value')::text) || '%')
      OR
      ((filters->>'name_type')::text = 'equals' AND filters->>'name_value' IS NOT NULL AND lower(name) = lower((filters->>'name_value')::text))
    )
    AND
    (
      (filters->>'search_term' IS NULL)
      OR
      (
        (id::text ILIKE '%' || lower((filters->>'search_term')::text) || '%') OR
        (lower(name) ILIKE '%' || lower((filters->>'search_term')::text) || '%')
      )
    )
  )data);
END;
$$;


ALTER FUNCTION "api"."get_sindri_saves"("filters" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_studies"("filters" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT id FROM internal.get_accessible_study_ids(false)));
  RETURN(SELECT array_to_json(array_agg(row_to_json(data)))
  FROM(
    SELECT s.*,
    (SELECT ARRAY(SELECT monad.id FROM internal.study_monads monad WHERE monad.study_id = s.id)) AS monad_ids,
    (SELECT ARRAY(SELECT scenario.id FROM internal.study_scenarios scenario WHERE scenario.study_id = s.id)) AS scenario_ids,
    (SELECT ARRAY(SELECT task.id FROM internal.study_tasks task WHERE task.study_id = s.id)) AS task_ids,
    (SELECT ARRAY(SELECT business_unit_id FROM internal.studies_access WHERE study_id = s.id AND business_unit_id IN (SELECT internal.get_business_unit_ids_downwards(false)))) AS accessible_by,
    (SELECT access_level FROM internal.studies_access WHERE study_id = s.id AND business_unit_id = (SELECT internal.get_own_business_unit_id())) AS access_level
    FROM internal.studies s
    WHERE 
    (
      (id IN (SELECT unnest(accessible_study_ids)))
    )
    AND
    (
      status <> 'archived'
    )
    AND
    (
      (filters->>'name_type' IS NULL)
      OR
      ((filters->>'name_type')::text = 'contain' AND filters->>'name_value' IS NOT NULL AND lower(name) ILIKE '%' || lower((filters->>'name_value')::text) || '%')
      OR
      ((filters->>'name_type')::text = 'not_contain' AND filters->>'name_value' IS NOT NULL AND lower(name) NOT ILIKE '%' || lower((filters->>'name_value')::text) || '%')
      OR
      ((filters->>'name_type')::text = 'equals' AND filters->>'name_value' IS NOT NULL AND lower(name) = lower((filters->>'name_value')::text))
    )
    AND
    (
      (filters->>'id_type' IS NULL)
      OR
      ((filters->>'id_type')::text = 'smaller' AND (filters->>'id_value_low')::bigint IS NOT NULL AND id < (filters->>'id_value_low')::bigint)
      OR
      ((filters->>'id_type')::text = 'greater' AND (filters->>'id_value_low')::bigint IS NOT NULL AND id > (filters->>'id_value_low')::bigint)
      OR
      ((filters->>'id_type')::text = 'in_between' AND (filters->>'id_value_low')::bigint IS NOT NULL AND (filters->>'id_value_high')::bigint IS NOT NULL AND id > (filters->>'id_value_low')::bigint AND id < (filters->>'id_value_high')::bigint)
      OR
      ((filters->>'id_type')::text = 'equals' AND (filters->>'id_value_low')::bigint IS NOT NULL AND id = (filters->>'id_value_low')::bigint)
    )
    AND
    (
      (filters->>'status_type' IS NULL)
      OR
      ((filters->>'status_type')::text = 'contain' AND filters->>'status_value' IS NOT NULL AND lower(status::text) ILIKE '%' || lower((filters->>'status_value')::text) || '%')
      OR
      ((filters->>'status_type')::text = 'not_contain' AND filters->>'status_value' IS NOT NULL AND lower(status::text) NOT ILIKE '%' || lower((filters->>'status_value')::text) || '%')
      OR
      ((filters->>'status_type')::text = 'equals' AND filters->>'status_value' IS NOT NULL AND lower(status::text) = lower((filters->>'status_value')::text))
    )
    AND
    (
      (filters->>'description_type' IS NULL)
      OR
      ((filters->>'description_type')::text = 'contain' AND filters->>'description_value' IS NOT NULL AND lower(name) ILIKE '%' || lower((filters->>'description_value')::text) || '%')
      OR
      ((filters->>'description_type')::text = 'not_contain' AND filters->>'description_value' IS NOT NULL AND lower(name) NOT ILIKE '%' || lower((filters->>'description_value')::text) || '%')
      OR
      ((filters->>'description_type')::text = 'equals' AND filters->>'description_value' IS NOT NULL AND lower(name) = lower((filters->>'description_value')::text))
    )
    AND
    (
      (filters->>'search_term' IS NULL)
      OR
      (
        (id::text ILIKE '%' || lower((filters->>'search_term')::text) || '%') OR
        (status::text ILIKE '%' || lower((filters->>'search_term')::text) || '%') OR
        (lower(name) ILIKE '%' || lower((filters->>'search_term')::text) || '%') OR
        (number_test_locations::text ILIKE '%' || lower((filters->>'search_term')::text) || '%') OR
        (lower(description) ILIKE '%' || lower((filters->>'search_term')::text) || '%')
      )
    )
  )data);
END;
$$;


ALTER FUNCTION "api"."get_studies"("filters" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_study"("id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(false) ids));
  RETURN(SELECT row_to_json(data)
  FROM(
    SELECT s.*,
    (SELECT api.get_study_monads(s.id)) as monads,
    (SELECT api.get_study_scenarios(s.id)) as scenarios,
    (SELECT ARRAY(SELECT task.id FROM internal.study_tasks task WHERE task.study_id = s.id)) AS task_ids,
    (SELECT ARRAY(SELECT business_unit_id FROM internal.studies_access WHERE study_id = s.id AND business_unit_id IN (SELECT internal.get_business_unit_ids_downwards(false)))) AS accessible_by,
    (SELECT access_level FROM internal.studies_access WHERE study_id = s.id AND business_unit_id = (SELECT internal.get_own_business_unit_id())) AS access_level
    FROM internal.studies s
    WHERE s.id = get_study.id
    AND s.id IN (SELECT unnest(accessible_study_ids))
  )data);
END;
$$;


ALTER FUNCTION "api"."get_study"("id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_study_computer"("physical_address" "text") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN(SELECT row_to_json(data)
  FROM(
    SELECT *
    FROM internal.study_computers comp
    WHERE comp.identifier = get_study_computer.physical_address
  )data);
END;
$$;


ALTER FUNCTION "api"."get_study_computer"("physical_address" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_study_computers"() RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN(SELECT array_to_json(array_agg(row_to_json(data)))
  FROM(
    SELECT * FROM internal.study_computers
  )data);
END;
$$;


ALTER FUNCTION "api"."get_study_computers"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_study_environment"("name" "text") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN(SELECT row_to_json(data)
  FROM(
    SELECT *
    FROM internal.study_environments env
    WHERE env.name = get_study_environment.name
  )data);
END;
$$;


ALTER FUNCTION "api"."get_study_environment"("name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_study_environments"() RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN(SELECT array_to_json(array_agg(row_to_json(data)))
  FROM(
    SELECT * FROM internal.study_environments
  )data);
END;
$$;


ALTER FUNCTION "api"."get_study_environments"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_study_monad"("id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(false) ids));
  RETURN(SELECT row_to_json(data)
  FROM(
    SELECT sm.*
    FROM internal.study_monads sm
    WHERE sm.id = get_study_monad.id
    AND sm.study_id IN (SELECT unnest(accessible_study_ids))
  )data);
END;
$$;


ALTER FUNCTION "api"."get_study_monad"("id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_study_monads"("study_id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT id FROM internal.get_accessible_study_ids(false)));
  RETURN(SELECT array_to_json(array_agg(row_to_json(data)))
  FROM(
    SELECT sm.*
    FROM internal.study_monads sm
    WHERE sm.study_id = get_study_monads.study_id AND sm.study_id IN (SELECT unnest(accessible_study_ids))
  )data);
END;
$$;


ALTER FUNCTION "api"."get_study_monads"("study_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_study_participant"("study_id" bigint, "custom_id" "text") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(false) ids));
  RETURN(SELECT row_to_json(data)
  FROM(
    SELECT sp.*
    FROM internal.study_participants sp
    WHERE sp.custom_id = get_study_participant.custom_id
    AND sp.study_id = get_study_participant.study_id
    AND sp.study_id IN (SELECT unnest(accessible_study_ids))
    LIMIT 1
  )data);
END;
$$;


ALTER FUNCTION "api"."get_study_participant"("study_id" bigint, "custom_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_study_participants"("monad_id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT id FROM internal.get_accessible_study_ids(false)));
  RETURN(SELECT array_to_json(array_agg(row_to_json(data)))
  FROM(
    SELECT sp.*
    FROM internal.study_participants sp
    WHERE sp.monad_id = get_study_participants.monad_id AND sp.study_id IN (SELECT unnest(accessible_study_ids))
  )data);
END;
$$;


ALTER FUNCTION "api"."get_study_participants"("monad_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_study_scenario"("id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(false) ids));
  RETURN(SELECT row_to_json(data)
  FROM(
    SELECT ss.*,
    (CASE
      WHEN (ss.environment_name IS NOT NULL) THEN (SELECT api.get_study_environment(ss.environment_name))
      ELSE null
    END) AS environment,
    (SELECT api.get_study_tasks(ss.id)) as tasks
    FROM internal.study_scenarios ss
    WHERE ss.id = get_study_scenario.id
    AND ss.study_id IN (SELECT unnest(accessible_study_ids))
  )data);
END;
$$;


ALTER FUNCTION "api"."get_study_scenario"("id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_study_scenarios"("study_id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT id FROM internal.get_accessible_study_ids(false)));
  RETURN(SELECT array_to_json(array_agg(row_to_json(data)))
  FROM(
    SELECT ss.*,
    (CASE
      WHEN (ss.environment_name IS NOT NULL) THEN (SELECT api.get_study_environment(ss.environment_name))
      ELSE null
    END) AS environment,
    (SELECT api.get_study_tasks(ss.id)) as tasks
    FROM internal.study_scenarios ss
    WHERE ss.study_id = get_study_scenarios.study_id AND ss.study_id IN (SELECT unnest(accessible_study_ids))
  )data);
END;
$$;


ALTER FUNCTION "api"."get_study_scenarios"("study_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_study_task"("id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(false) ids));
  RETURN(SELECT row_to_json(data)
  FROM(
    SELECT st.*
    FROM internal.study_tasks st
    WHERE st.id = get_study_task.id
    AND st.study_id IN (SELECT unnest(accessible_study_ids))
  )data);
END;
$$;


ALTER FUNCTION "api"."get_study_task"("id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_study_tasks"("scenario_id" bigint) RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT id FROM internal.get_accessible_study_ids(false)));
  RETURN(SELECT array_to_json(array_agg(row_to_json(data)))
  FROM(
    SELECT st.*
    FROM internal.study_tasks st
    WHERE st.scenario_id = get_study_tasks.scenario_id AND st.study_id IN (SELECT unnest(accessible_study_ids))
  )data);
END;
$$;


ALTER FUNCTION "api"."get_study_tasks"("scenario_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."get_user_application_permissions"("application_name" "text") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN(SELECT permission_json
  FROM internal.user_application_permissions uap
  WHERE uap.application_name = get_user_application_permissions.application_name AND user_id = (SELECT auth.uid()));
END;
$$;


ALTER FUNCTION "api"."get_user_application_permissions"("application_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."migrate_product"("product" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_product_category_ids bigint[];
  result bigint;
BEGIN
  if ((SELECT internal.get_is_admin()) is not true) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  end if;
  INSERT INTO internal.products(id, category_id, custom_id, name, price_tag_text, brand, manufacturer, quantity, note, width, height, depth, price, created_at, updated_at)
  VALUES
  (
    (product->>'id')::bigint,
    (product->>'category_id')::bigint,
    (product->>'custom_id')::text,
    (product->>'name')::text,
    (product->>'price_tag_text')::text,
    (product->>'brand')::text,
    (product->>'manufacturer')::text,
    (product->>'quantity')::text,
    (product->>'note')::text,
    (product->>'width')::float,
    (product->>'height')::float,
    (product->>'depth')::float,
    (product->>'price')::float,
    (product->>'created_at')::timestamp,
    (product->>'updated_at')::timestamp
  )
  RETURNING id INTO result;
  RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
END;
$$;


ALTER FUNCTION "api"."migrate_product"("product" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."migrate_product_category"("product_category" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  business_unit_ids_to_grant_access bigint[];
  sub_business_unit_ids_without_own bigint[];
  result bigint;
BEGIN
  if ((SELECT internal.get_is_admin()) is not true) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  end if;
  INSERT INTO internal.product_categories(id, name, parent_id)
  VALUES ((product_category->>'id')::bigint, (product_category->>'name')::text, (product_category->>'parent_id')::bigint)
  RETURNING id INTO result;

  if product_category->>'accessible_by' IS NOT NULL then
    business_unit_ids_to_grant_access := ARRAY(SELECT (jsonb_array_elements_text((product_category->>'accessible_by')::jsonb))::bigint);
    sub_business_unit_ids_without_own := (SELECT ARRAY(SELECT id FROM internal.get_business_unit_ids_downwards(false)));

    DELETE FROM internal.product_categories_access 
    WHERE business_unit_id IN (SELECT unnest(sub_business_unit_ids_without_own)) 
    AND business_unit_id NOT IN (SELECT unnest(business_unit_ids_to_grant_access)) 
    AND product_category_id = result;

    INSERT INTO internal.product_categories_access(business_unit_id, product_category_id)
    SELECT s.id, result 
    FROM unnest(business_unit_ids_to_grant_access) AS s(id)
    WHERE NOT EXISTS (
      SELECT * 
      FROM internal.product_categories_access 
      WHERE business_unit_id = s.id
        AND product_category_id = result
    )
    AND s.id in (SELECT unnest(sub_business_unit_ids_without_own));
  end if;

  if product_category->>'read_only' IS NOT NULL then
    UPDATE internal.product_categories_access SET access_level = 'read'::internal.access_level WHERE product_category_id = result AND business_unit_id IN (SELECT unnest(ARRAY(SELECT (jsonb_array_elements_text((product_category->>'read_only')::jsonb))::bigint)));
  end if;
  RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
END;
$$;


ALTER FUNCTION "api"."migrate_product_category"("product_category" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."migrate_sindri_save"("sindri_save" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  result bigint;
BEGIN
  if ((SELECT internal.get_is_admin()) is not true) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  end if;
  INSERT INTO internal.sindri_saves(id, folder_id, name, content, updated_at, created_at)
  VALUES 
  (
    (sindri_save->>'id')::bigint,
    (sindri_save->>'folder_id')::bigint,
    (sindri_save->>'name')::text,
    (sindri_save->>'content')::text,
    (sindri_save->>'updated_at')::timestamp,
    (sindri_save->>'created_at')::timestamp
  )
  RETURNING id INTO result;
  RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
END;
$$;


ALTER FUNCTION "api"."migrate_sindri_save"("sindri_save" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."migrate_study"("study" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  business_unit_ids_to_grant_access bigint[];
  sub_business_unit_ids_without_own bigint[];
  monads json;
  monad json;
  scenarios json;
  scenario json;
  tasks json;
  task json;
  i integer;
  study_result bigint;
  scenario_result bigint;
BEGIN
  if ((SELECT internal.get_is_admin()) is not true) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  end if;
  INSERT INTO internal.studies(id, created_at, updated_at, name, description, number_test_locations, number_participants, status)
  VALUES 
  (
    (study->>'id')::bigint,
    (study->>'created_at')::timestamp,
    (study->>'updated_at')::timestamp,
    (study->>'name')::text,
    (study->>'description')::text,
    (study->>'number_test_locations')::bigint,
    (study->>'number_participants')::bigint,
    (study->>'status')::internal.study_status
  )
  RETURNING id INTO study_result;

  monads := study->'monads';
  if monads IS NOT NULL then
    FOR i IN 0..JSON_ARRAY_LENGTH(monads) - 1 LOOP
      monad := monads->i;
      INSERT INTO internal.study_monads(id, study_id, name, description, participant_goal, scenario_orders, order_in_study, distributions)
      VALUES 
      (
        (monad->>'id')::bigint,
        study_result,
        (monad->>'name')::text,
        (monad->>'description')::text,
        (monad->>'participant_goal')::bigint,
        (monad->>'scenario_orders')::json,
        (monad->>'order_in_study')::bigint,
        (monad->>'distributions')::json
      ); 
    END LOOP;
  end if;

  scenarios := study->'scenarios';
  if scenarios IS NOT NULL then
    FOR i IN 0..JSON_ARRAY_LENGTH(scenarios) - 1 LOOP
      scenario := scenarios->i;
        INSERT INTO internal.study_scenarios(id, study_id, name, description, optional, environment_name, order_in_study)
        VALUES 
        (
          (scenario->>'id')::bigint,
          study_result,
          (scenario->>'name')::text,
          (scenario->>'description')::text,
          (scenario->>'optional')::boolean,
          (scenario->'environment')->>'name'::text,
          (scenario->>'order_in_study')::bigint
        )
        RETURNING id INTO scenario_result;
        tasks := scenario->'tasks';
        if tasks IS NOT NULL then
          FOR i IN 0..JSON_ARRAY_LENGTH(tasks) - 1 LOOP
            task := tasks->i;
            INSERT INTO internal.study_tasks(id, study_id, scenario_id, name, description, task_text, start_position_x, start_position_y, start_position_z, product_transport, buying_restriction, buying_limit, blind_limit, teleport_range, set_time_stamp_button, order_in_scenario, start_rotation, optional)
            VALUES 
            (
              (task->>'id')::bigint,
              study_result,
              scenario_result,
              (task->>'name')::text,
              (task->>'description')::text,
              (task->>'task_text')::text,
              (task->>'start_position_x')::float,
              (task->>'start_position_y')::float,
              (task->>'start_position_z')::float,
              (task->>'product_transport')::internal.product_transport,
              (task->>'buying_restriction')::internal.buying_restriction,
              (task->>'buying_limit')::float,
              (task->>'blind_limit')::boolean,
              (task->>'teleport_range')::float,
              (task->>'set_time_stamp_button')::boolean,
              (task->>'order_in_scenario')::bigint,
              (task->>'start_rotation')::float,
              (task->>'optional')::boolean
            );
          END LOOP;
        end if;
    END LOOP;
  end if;

  if study->>'accessible_by' IS NOT NULL then
      business_unit_ids_to_grant_access := ARRAY(SELECT (jsonb_array_elements_text((study->>'accessible_by')::jsonb))::bigint);
      sub_business_unit_ids_without_own := (SELECT ARRAY(SELECT id FROM internal.get_business_unit_ids_downwards(false)));

      DELETE FROM internal.studies_access 
      WHERE business_unit_id IN (SELECT unnest(sub_business_unit_ids_without_own)) 
      AND business_unit_id NOT IN (SELECT unnest(business_unit_ids_to_grant_access)) 
      AND study_id = study_result;

      INSERT INTO internal.studies_access(business_unit_id, study_id)
      SELECT s.id, study_result 
      FROM unnest(business_unit_ids_to_grant_access) AS s(id)
      WHERE NOT EXISTS (
        SELECT * 
        FROM internal.studies_access 
        WHERE business_unit_id = s.id
          AND study_id = study_result
      )
      AND s.id IN (SELECT unnest(sub_business_unit_ids_without_own));
    end if;
  RETURN(SELECT json_build_object ('response_code', 200, 'id', study_result));
END;
$$;


ALTER FUNCTION "api"."migrate_study"("study" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."ping"("application_name" "text", "computer_hash" "text") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  max_connection_defining_business_unit json;
  requesting_user_id uuid;
  bu_id bigint;
  max bigint;
  current bigint;
BEGIN
  requesting_user_id := (SELECT auth.uid());
  max_connection_defining_business_unit := (SELECT internal.get_connection_defining_business_unit(ping.application_name));
  bu_id := (SELECT (max_connection_defining_business_unit ->> 'id'));
  max := (SELECT (max_connection_defining_business_unit ->> 'max_connections'));
  current := (SELECT COUNT(*) FROM internal.active_users au WHERE au.application_name = ping.application_name AND business_unit_id = bu_id AND user_id != requesting_user_id AND last_active_at > NOW() - INTERVAL '1 MINUTE');

  if max IS NULL OR max = 0 then
    RETURN(SELECT json_build_object ('response_code', 410, 'message', 'Not allowed to ping application.'));
  elseif current >= max then
    RETURN(SELECT json_build_object ('response_code', 411, 'message', 'Max concurrent connections reached.'));
  elseif (SELECT COUNT(*) FROM internal.active_users au WHERE au.application_name = ping.application_name AND business_unit_id = bu_id AND user_id = requesting_user_id AND last_computer_hash != computer_hash AND last_active_at > NOW() - INTERVAL '1 MINUTE') > 0 then
    RETURN(SELECT json_build_object ('response_code', 413, 'message', 'Already active on another machine.'));
  else
    INSERT INTO internal.active_users (user_id, application_name, business_unit_id, last_active_at, last_computer_hash)
    VALUES (requesting_user_id, ping.application_name, bu_id, now(), computer_hash)
    ON CONFLICT ON CONSTRAINT active_users_pkey DO UPDATE
    SET last_active_at = now(), last_computer_hash = computer_hash;
    RETURN(SELECT json_build_object ('response_code', 200, 'message', 'OK'));
  end if;
END;
$$;


ALTER FUNCTION "api"."ping"("application_name" "text", "computer_hash" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."unping"("application_name" "text") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  max_connection_defining_business_unit json;
  max bigint;
BEGIN
  max_connection_defining_business_unit := (SELECT internal.get_connection_defining_business_unit(unping.application_name));
  max := (SELECT (max_connection_defining_business_unit ->> 'max_connections'));
  if max is null or max = 0 then
    RETURN(SELECT json_build_object ('response_code', 410, 'message', 'Not allowed to ping application.'));
  else
    UPDATE internal.active_users au SET last_active_at = null, last_computer_hash = null WHERE au.application_name = unping.application_name AND user_id = auth.uid();
    RETURN(SELECT json_build_object ('response_code', 200, 'message', 'OK'));
  end if;
END;
$$;


ALTER FUNCTION "api"."unping"("application_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."update_application"("name" "text", "application" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  result text;
BEGIN
  if ((SELECT internal.get_is_admin()) is not true) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  elseif (application->>'beta_version_id' IS NOT NULL AND (SELECT COUNT(id) FROM internal.application_versions WHERE id = (application->>'beta_version_id')::bigint) = 0) then
    RETURN(SELECT json_build_object ('response_code', 404, 'message', 'Not found.'));
  elseif (application->>'release_version_id' IS NOT NULL AND (SELECT COUNT(id) FROM internal.application_versions WHERE id = (application->>'release_version_id')::bigint) = 0) then
    RETURN(SELECT json_build_object ('response_code', 404, 'message', 'Not found.'));
  else
    UPDATE internal.applications a SET
      beta_version_id = (application->>'beta_version_id')::bigint,
      release_version_id = (application->>'release_version_id')::bigint
    WHERE a.name = update_application.name RETURNING a.name into result;
    RETURN(SELECT json_build_object ('response_code', 200, 'name', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."update_application"("name" "text", "application" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."update_application_version"("id" bigint, "version" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  result bigint;
BEGIN
  if ((SELECT internal.get_is_admin()) is not true) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    UPDATE internal.application_versions av SET
    application_name = (update_application_version.version->>'application_name')::text,
    version = (update_application_version.version->>'version')::text
    WHERE av.id = update_application_version.id
    RETURNING av.id INTO result;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."update_application_version"("id" bigint, "version" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."update_application_version_file"("id" bigint, "file_key" "text") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  result bigint;
BEGIN
  if ((SELECT internal.get_is_admin()) is not true) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    UPDATE internal.application_versions av SET file_key = update_application_version_file.file_key WHERE av.id = update_application_version_file.id
    RETURNING av.id into result;
    if(result is null) then
      RETURN(SELECT json_build_object ('response_code', 404, 'message', 'Not found.'));
    else
      RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
    end if;
  end if;
END;
$$;


ALTER FUNCTION "api"."update_application_version_file"("id" bigint, "file_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."update_product"("id" bigint, "product" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_product_category_ids bigint[];
  result bigint;
BEGIN
  accessible_product_category_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_product_category_ids(true) ids));
  if product->>'category_id' IS NOT NULL AND (product->>'category_id')::bigint NOT IN (SELECT unnest(accessible_product_category_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    UPDATE internal.products p SET
    category_id = (product->>'category_id')::bigint,
    custom_id = (product->>'custom_id')::text,
    name = (product->>'name')::text,
    price_tag_text = (product->>'price_tag_text')::text,
    brand = (product->>'brand')::text,
    manufacturer = (product->>'manufacturer')::text,
    quantity = (product->>'quantity')::text,
    note = (product->>'note')::text,
    width = (product->>'width')::float,
    height = (product->>'height')::float,
    depth = (product->>'depth')::float,
    price = (product->>'price')::float
    WHERE p.id = update_product.id AND category_id IN (SELECT unnest(accessible_product_category_ids))
    RETURNING p.id INTO result;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."update_product"("id" bigint, "product" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."update_product_browser_image_file"("id" bigint, "file_key" "text") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_product_category_ids bigint[];
  result bigint;
BEGIN
  accessible_product_category_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_product_category_ids(true) ids));
  UPDATE internal.products p SET 
    browser_image_key = file_key,
    updated_at = now()
  WHERE p.id = update_product_browser_image_file.id AND category_id IN (SELECT unnest(accessible_product_category_ids))
  RETURNING p.id into result;
  if(result is null) then
    RETURN(SELECT json_build_object ('response_code', 404, 'message', 'Not found.'));
  else
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."update_product_browser_image_file"("id" bigint, "file_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."update_product_category"("id" bigint, "product_category" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  business_unit_ids_to_grant_access bigint[];
  sub_business_unit_ids_without_own bigint[];
  accessible_product_category_ids bigint[];
  child_categories bigint[];
  result bigint;
BEGIN
  accessible_product_category_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_product_category_ids(true) ids));
  child_categories := (SELECT ARRAY(SELECT ids.id FROM internal.get_product_category_ids_downwards(update_product_category.id, false, true, accessible_product_category_ids) ids));
  if (product_category->>'parent_id' IS NOT NULL AND (product_category->>'parent_id')::bigint NOT IN (SELECT unnest(accessible_product_category_ids))) OR
     (NOT (child_categories <@ accessible_product_category_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    UPDATE internal.product_categories pc SET
      name = (product_category->>'name')::text,
      parent_id = (product_category->>'parent_id')::bigint
    WHERE
      pc.id = update_product_category.id AND
      pc.id IN (SELECT unnest(accessible_product_category_ids))
    RETURNING pc.id into result;
    
    if product_category->>'accessible_by' IS NOT NULL then
      business_unit_ids_to_grant_access := ARRAY(SELECT (jsonb_array_elements_text((product_category->>'accessible_by')::jsonb))::bigint);
      sub_business_unit_ids_without_own := (SELECT ARRAY(SELECT ids.id FROM internal.get_business_unit_ids_downwards(false) ids));

      DELETE FROM internal.product_categories_access 
      WHERE business_unit_id IN (SELECT unnest(sub_business_unit_ids_without_own)) 
      AND business_unit_id NOT IN (SELECT unnest(business_unit_ids_to_grant_access)) 
      AND product_category_id = update_product_category.id;

      INSERT INTO internal.product_categories_access(business_unit_id, product_category_id)
      SELECT s.id, update_product_category.id 
      FROM unnest(business_unit_ids_to_grant_access) AS s(id)
      WHERE NOT EXISTS (
        SELECT * 
        FROM internal.product_categories_access 
        WHERE business_unit_id = s.id
          AND product_category_id = update_product_category.id
      )
      AND s.id IN (SELECT unnest(sub_business_unit_ids_without_own));
    end if;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."update_product_category"("id" bigint, "product_category" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."update_product_shelf_image_file"("id" bigint, "file_key" "text") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_product_category_ids bigint[];
  result bigint;
BEGIN
  accessible_product_category_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_product_category_ids(true) ids));
  UPDATE internal.products p SET
    shelf_image_key = file_key,
    updated_at = now()
  WHERE p.id = update_product_shelf_image_file.id AND category_id IN (SELECT unnest(accessible_product_category_ids))
  RETURNING p.id into result;
  if(result is null) then
    RETURN(SELECT json_build_object ('response_code', 404, 'message', 'Not found.'));
  else
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."update_product_shelf_image_file"("id" bigint, "file_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."update_sindri_folder"("id" bigint, "sindri_folder" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  business_unit_ids_to_grant_access bigint[];
  sub_business_unit_ids_without_own bigint[];
  accessible_sindri_folder_ids bigint[];
  child_folders bigint[];
  result bigint;
BEGIN
  accessible_sindri_folder_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_sindri_folder_ids(true) ids));
  child_folders := (SELECT ARRAY(SELECT ids.id FROM internal.get_sindri_folder_ids_downwards(update_sindri_folder.id, false, true, accessible_sindri_folder_ids) ids));
  if (sindri_folder->>'parent_id' IS NOT NULL AND (sindri_folder->>'parent_id')::bigint NOT IN (SELECT unnest(accessible_sindri_folder_ids))) OR
     (NOT (child_folders <@ accessible_sindri_folder_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    UPDATE internal.sindri_folders sf SET
      name = (sindri_folder->>'name')::text,
      parent_id = (sindri_folder->>'parent_id')::bigint
    WHERE
      sf.id = update_sindri_folder.id AND
      sf.id IN (SELECT unnest(accessible_sindri_folder_ids))
    RETURNING sf.id into result;
    
    if sindri_folder->>'accessible_by' IS NOT NULL then
      business_unit_ids_to_grant_access := ARRAY(SELECT (jsonb_array_elements_text((sindri_folder->>'accessible_by')::jsonb))::bigint);
      sub_business_unit_ids_without_own := (SELECT ARRAY(SELECT ids.id FROM internal.get_business_unit_ids_downwards(false) ids));

      DELETE FROM internal.sindri_folders_access 
      WHERE business_unit_id IN (SELECT unnest(sub_business_unit_ids_without_own)) 
      AND business_unit_id NOT IN (SELECT unnest(business_unit_ids_to_grant_access)) 
      AND sindri_folder_id = update_sindri_folder.id;

      INSERT INTO internal.sindri_folders_access(business_unit_id, sindri_folder_id)
      SELECT s.id, update_sindri_folder.id 
      FROM unnest(business_unit_ids_to_grant_access) AS s(id)
      WHERE NOT EXISTS (
        SELECT * 
        FROM internal.sindri_folders_access 
        WHERE business_unit_id = s.id
          AND sindri_folder_id = update_sindri_folder.id
      )
      AND s.id IN (SELECT unnest(sub_business_unit_ids_without_own));
    end if;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."update_sindri_folder"("id" bigint, "sindri_folder" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."update_sindri_save"("id" bigint, "sindri_save" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_sindri_folder_ids bigint[];
  result bigint;
BEGIN
  accessible_sindri_folder_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_sindri_folder_ids(true) ids));
  if sindri_save->>'folder_id' IS NULL OR (sindri_save->>'folder_id')::bigint NOT IN (SELECT unnest(accessible_sindri_folder_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    UPDATE internal.sindri_saves ss SET 
      name = (sindri_save->>'name')::text,
      folder_id = (sindri_save->>'folder_id')::bigint,
      content = (sindri_save->>'content')::text,
      updated_at = now()
    WHERE ss.id = update_sindri_save.id AND folder_id IN (SELECT unnest(accessible_sindri_folder_ids)) RETURNING ss.id into result;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."update_sindri_save"("id" bigint, "sindri_save" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."update_study"("id" bigint, "study" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  business_unit_ids_to_grant_access bigint[];
  sub_business_unit_ids_without_own bigint[];
  accessible_study_ids bigint[];
  monads json;
  monad json;
  scenarios json;
  scenario json;
  i integer;
  result bigint;
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(true) ids));
  if id NOT IN (SELECT unnest(accessible_study_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    UPDATE internal.studies s SET 
      name = (study->>'name')::text,
      description = (study->>'description')::text,
      number_test_locations = (study->>'number_test_locations')::bigint,
      number_participants = (study->>'number_participants')::bigint,
      status = (study->>'status')::internal.study_status
    WHERE s.id = update_study.id RETURNING s.id into result;

    monads := study->'monads';
    if monads IS NOT NULL then
      FOR i IN 0..JSON_ARRAY_LENGTH(monads) - 1 LOOP
        monad := monads->i;
        if (monad->>'id')::bigint = 0 then
          PERFORM api.create_study_monad(id, monad);
        else
          PERFORM api.update_study_monad(id, (monad->>'id')::bigint, monad);
        end if;
      END LOOP;
    end if;

    scenarios := study->'scenarios';
    if scenarios IS NOT NULL then
      FOR i IN 0..JSON_ARRAY_LENGTH(scenarios) - 1 LOOP
        scenario := scenarios->i;
        if (scenario->>'id')::bigint = 0 then
          PERFORM api.create_study_scenario(id, scenario);
        else
          PERFORM api.update_study_scenario(id, (scenario->>'id')::bigint, scenario);
        end if;
      END LOOP;
    end if;

    if study->>'accessible_by' IS NOT NULL then
      business_unit_ids_to_grant_access := ARRAY(SELECT (jsonb_array_elements_text((study->>'accessible_by')::jsonb))::bigint);
      sub_business_unit_ids_without_own := (SELECT ARRAY(SELECT ids.id FROM internal.get_business_unit_ids_downwards(false) ids));

      DELETE FROM internal.studies_access 
      WHERE business_unit_id IN (SELECT unnest(sub_business_unit_ids_without_own)) 
      AND business_unit_id NOT IN (SELECT unnest(business_unit_ids_to_grant_access)) 
      AND study_id = result;

      INSERT INTO internal.studies_access(business_unit_id, study_id)
      SELECT s.id, result 
      FROM unnest(business_unit_ids_to_grant_access) AS s(id)
      WHERE NOT EXISTS (
        SELECT * 
        FROM internal.studies_access 
        WHERE business_unit_id = s.id
          AND study_id = result
      )
      AND s.id IN (SELECT unnest(sub_business_unit_ids_without_own));
    end if;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."update_study"("id" bigint, "study" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."update_study_computer"("id" bigint, "computer" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  result bigint;
BEGIN
  if ((SELECT internal.get_is_admin()) is not true) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    UPDATE internal.study_computers comp SET
    name = (computer->>'name')::text,
    description = (computer->>'description')::text,
    location = (computer->>'location')::text,
    cpu = (computer->>'cpu')::text,
    gpu = (computer->>'gpu')::text,
    identifier = (computer->>'identifier')::text,
    participant_id_min = (computer->>'participant_id_min')::bigint,
    participant_id_max = (computer->>'participant_id_max')::bigint,
    study_id = (computer->>'study_id')::bigint
    WHERE comp.id = update_study_computer.id
    RETURNING comp.id INTO result;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."update_study_computer"("id" bigint, "computer" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."update_study_environment"("name" "text", "environment" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  result text;
BEGIN
  if ((SELECT internal.get_is_admin()) is not true) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    UPDATE internal.study_environments env SET
    description = (environment->>'description')::text,
    width = (environment->>'width')::float,
    height = (environment->>'height')::float,
    depth = (environment->>'depth')::float,
    center_x = (environment->>'center_x')::float,
    center_y = (environment->>'center_y')::float,
    center_z = (environment->>'center_z')::float
    WHERE env.name = update_study_environment.name
    RETURNING env.name INTO result;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."update_study_environment"("name" "text", "environment" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."update_study_environment_file"("name" "text", "file_key" "text") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  result text;
BEGIN
  if ((SELECT internal.get_is_admin()) is not true) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    UPDATE internal.study_environments env SET file_key = update_study_environment_file.file_key WHERE env.name = update_study_environment_file.name
    RETURNING env.name into result;
    if(result is null) then
      RETURN(SELECT json_build_object ('response_code', 404, 'message', 'Not found.'));
    else
      RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
    end if;
  end if;
END;
$$;


ALTER FUNCTION "api"."update_study_environment_file"("name" "text", "file_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."update_study_file"("id" bigint, "file_key" "text") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
  result bigint;
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(true) ids));
  if id NOT IN (SELECT unnest(accessible_study_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    UPDATE internal.studies s SET
      file_key = update_study_file.file_key,
      updated_at = now()
    WHERE s.id = update_study_file.id
    RETURNING s.id into result;
    if(result is null) then
      RETURN(SELECT json_build_object ('response_code', 404, 'message', 'Not found.'));
    else
      RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
    end if;
  end if;
END;
$$;


ALTER FUNCTION "api"."update_study_file"("id" bigint, "file_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."update_study_monad"("study_id" bigint, "id" bigint, "study_monad" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
  result bigint;
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(true) ids));
  if study_id IS NULL OR study_id NOT IN (SELECT unnest(accessible_study_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    UPDATE internal.study_monads sm SET 
      name = (study_monad->>'name')::text,
      description = (study_monad->>'description')::text,
      participant_goal = (study_monad->>'participant_goal')::bigint,
      distributions = (study_monad->>'distributions')::json,
      scenario_orders = (study_monad->>'scenario_orders')::json,
      order_in_study = (study_monad->>'order_in_study')::bigint
    WHERE sm.id = update_study_monad.id RETURNING sm.id into result;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."update_study_monad"("study_id" bigint, "id" bigint, "study_monad" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."update_study_participant"("id" bigint, "study_participant" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
  result bigint;
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(true) ids));
  if (SELECT sp.study_id FROM internal.study_participants sp WHERE sp.id = update_study_participant.id) NOT IN (SELECT unnest(accessible_study_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    UPDATE internal.study_participants sp SET 
      recorded_by = (study_participant->>'recorded_by')::bigint,
      fixation_data_valid = (study_participant->>'fixation_data_valid')::boolean,
      position_data_valid = (study_participant->>'position_data_valid')::boolean,
      properties = (study_participant->>'properties')::json,
      finished_scenario_ids = (study_participant->>'finished_scenario_ids')::json,
      finished_task_ids = (study_participant->>'finished_task_ids')::json,
      all_scenarios_finished = (study_participant->>'all_scenarios_finished')::boolean,
      all_tasks_finished = (study_participant->>'all_tasks_finished')::boolean
    WHERE sp.id = update_study_participant.id RETURNING sp.id into result;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."update_study_participant"("id" bigint, "study_participant" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."update_study_participant_file"("id" bigint, "file_key" "text") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
  result bigint;
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(true) ids));
  if (SELECT sp.study_id FROM internal.study_participants sp WHERE sp.id = update_study_participant_file.id) NOT IN (SELECT unnest(accessible_study_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    UPDATE internal.study_participants sp SET
      file_key = update_study_participant_file.file_key,
      updated_at = now()
    WHERE sp.id = update_study_participant_file.id
    RETURNING sp.id into result;
    if(result is null) then
      RETURN(SELECT json_build_object ('response_code', 404, 'message', 'Not found.'));
    else
      RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
    end if;
  end if;
END;
$$;


ALTER FUNCTION "api"."update_study_participant_file"("id" bigint, "file_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."update_study_scenario"("study_id" bigint, "id" bigint, "study_scenario" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
  tasks json;
  task json;
  i integer;
  result bigint;
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(true) ids));
  if study_id IS NULL OR study_id NOT IN (SELECT unnest(accessible_study_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    UPDATE internal.study_scenarios ss SET 
      name = (study_scenario->>'name')::text,
      order_in_study = (study_scenario->>'order_in_study')::bigint,
      description = (study_scenario->>'description')::text,
      optional = (study_scenario->>'optional')::boolean,
      environment_name = (study_scenario->'environment')->>'name'::text
    WHERE ss.id = update_study_scenario.id RETURNING ss.id into result;
    tasks := study_scenario->'tasks';
    if tasks IS NOT NULL then
      FOR i IN 0..JSON_ARRAY_LENGTH(tasks) - 1 LOOP
        task := tasks->i;
        if (task->>'id')::bigint = 0 then
          PERFORM api.create_study_task(study_id, id, task);
        else
          PERFORM api.update_study_task(study_id, (task->>'id')::bigint, task);
        end if;
      END LOOP;
    end if;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."update_study_scenario"("study_id" bigint, "id" bigint, "study_scenario" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "api"."update_study_task"("study_id" bigint, "id" bigint, "study_task" "json") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  accessible_study_ids bigint[];
  result bigint;
BEGIN
  accessible_study_ids := (SELECT ARRAY(SELECT ids.id FROM internal.get_accessible_study_ids(true) ids));
  if study_id IS NULL OR study_id NOT IN (SELECT unnest(accessible_study_ids)) then
    RETURN(SELECT json_build_object ('response_code', 412, 'message', 'Not permitted.'));
  else
    UPDATE internal.study_tasks st SET 
      name = (study_task->>'name')::text,
      description = (study_task->>'description')::text,
      task_text = (study_task->>'task_text')::text,
      start_position_x = (study_task->>'start_position_x')::float,
      start_position_y = (study_task->>'start_position_y')::float,
      start_position_z = (study_task->>'start_position_z')::float,
      product_transport = (study_task->>'product_transport')::internal.product_transport,
      buying_restriction = (study_task->>'buying_restriction')::internal.buying_restriction,
      buying_limit = (study_task->>'buying_limit')::float,
      blind_limit = (study_task->>'blind_limit')::boolean,
      teleport_range = (study_task->>'teleport_range')::float,
      set_time_stamp_button = (study_task->>'set_time_stamp_button')::boolean,
      order_in_scenario = (study_task->>'order_in_scenario')::bigint,
      start_rotation = (study_task->>'start_rotation')::float,
      optional = (study_task->>'optional')::boolean
    WHERE st.id = update_study_task.id RETURNING st.id into result;
    RETURN(SELECT json_build_object ('response_code', 200, 'id', result));
  end if;
END;
$$;


ALTER FUNCTION "api"."update_study_task"("study_id" bigint, "id" bigint, "study_task" "json") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."delete_storage_file"("file_key" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  url text;
  headers jsonb;
  response json;
  service_key text;
BEGIN
  service_key := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name =  'SUPABASE_SERVICE_ROLE_KEY');
  url := 'https://cftqsgtaiakmnapiflmf.supabase.co/storage/v1/object/' || file_key;
  headers := jsonb_build_object('Authorization', 'Bearer ' || service_key, 'Accept', 'application/json');
  SELECT net.http_delete(url:=url, headers:=headers) into response;
END;
$$;


ALTER FUNCTION "internal"."delete_storage_file"("file_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_accessible_product_category_ids"("write_only" boolean) RETURNS TABLE("id" bigint)
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN QUERY
  SELECT product_category_id
  FROM internal.product_categories_access
  WHERE business_unit_id = (SELECT internal.get_own_business_unit_id()) AND (NOT write_only OR access_level = 'write');
END;
$$;


ALTER FUNCTION "internal"."get_accessible_product_category_ids"("write_only" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_accessible_sindri_folder_ids"("write_only" boolean) RETURNS TABLE("id" bigint)
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN QUERY
  SELECT sindri_folder_id
  FROM internal.sindri_folders_access
  WHERE business_unit_id = (SELECT internal.get_own_business_unit_id()) AND (NOT write_only OR access_level = 'write');
END;
$$;


ALTER FUNCTION "internal"."get_accessible_sindri_folder_ids"("write_only" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_accessible_study_ids"("write_only" boolean) RETURNS TABLE("id" bigint)
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN QUERY
  SELECT study_id
  FROM internal.studies_access
  WHERE business_unit_id = (SELECT internal.get_own_business_unit_id()) AND (NOT write_only OR access_level = 'write');
END;
$$;


ALTER FUNCTION "internal"."get_accessible_study_ids"("write_only" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_business_unit_ids_downwards"("include_own" boolean) RETURNS TABLE("id" bigint)
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE parent_recursion AS
  (
    SELECT business_unit_id 
    FROM internal.additional_user_information aui
    WHERE (SELECT aui.id = auth.uid())     

    UNION ALL      

    SELECT bu.id 
    FROM parent_recursion, internal.business_units bu
    WHERE parent_recursion.business_unit_id = bu.parent_id
  )
  SELECT business_unit_id FROM parent_recursion
  WHERE (include_own OR business_unit_id != (SELECT internal.get_own_business_unit_id()));
END;
$$;


ALTER FUNCTION "internal"."get_business_unit_ids_downwards"("include_own" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_business_unit_ids_upwards"("include_own" boolean) RETURNS TABLE("id" bigint)
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE parent_recursion AS
  (
    SELECT business_unit_id 
    FROM internal.additional_user_information aui
    WHERE (SELECT aui.id = auth.uid())    

    UNION ALL      

    SELECT bu.parent_id 
    FROM parent_recursion pr
    JOIN internal.business_units bu ON pr.business_unit_id = bu.id
    WHERE bu.parent_id IS NOT NULL
  )
  SELECT business_unit_id FROM parent_recursion
  WHERE (include_own OR business_unit_id != (SELECT internal.get_own_business_unit_id()));
END;
$$;


ALTER FUNCTION "internal"."get_business_unit_ids_upwards"("include_own" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_category_id_parent_path"("category_id" bigint, "accessible_product_category_ids" bigint[], "include_own" boolean) RETURNS bigint[]
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
    path bigint[] := ARRAY[category_id];
    parent bigint;
BEGIN
  parent := (SELECT parent_id FROM internal.product_categories WHERE id = category_id AND id in (SELECT UNNEST(accessible_product_category_ids)));
  WHILE parent IS NOT NULL LOOP
    path := ARRAY_APPEND(path, parent);
    parent := (SELECT parent_id FROM internal.product_categories WHERE id = parent AND id in (SELECT UNNEST(accessible_product_category_ids)));
    END LOOP;
    if(NOT include_own) then
    path := (SELECT array_remove(path, category_id));
    end if;
    RETURN array(
    select path[i]
    from generate_subscripts(path, 1) as indices(i)
    --where include_own OR i != category_id
    order by i desc
    );
END;
$$;


ALTER FUNCTION "internal"."get_category_id_parent_path"("category_id" bigint, "accessible_product_category_ids" bigint[], "include_own" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_connection_defining_business_unit"("application_name" "text") RETURNS "json"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  result json;
BEGIN
  WITH RECURSIVE parent_recursion AS
  (
    SELECT bu.id, bu.parent_id, mcc.application_name, mcc.max_connections
    FROM internal.business_units bu
    LEFT JOIN internal.max_concurrent_connections mcc
    ON bu.id = mcc.business_unit_id AND mcc.application_name = get_connection_defining_business_unit.application_name
    WHERE bu.id = (SELECT internal.get_own_business_unit_id())
  
    UNION ALL

    SELECT bu.id, bu.parent_id, mcc.application_name, mcc.max_connections
    FROM internal.business_units bu
    JOIN parent_recursion p
    ON bu.id = p.parent_id
    LEFT JOIN internal.max_concurrent_connections mcc
    ON bu.id = mcc.business_unit_id AND mcc.application_name = get_connection_defining_business_unit.application_name
  )
  SELECT row_to_json(data)
  FROM(
    SELECT p.*
    FROM parent_recursion p
    WHERE p.application_name = get_connection_defining_business_unit.application_name
    LIMIT 1
  )data into result;
  RETURN result;
END;
$$;


ALTER FUNCTION "internal"."get_connection_defining_business_unit"("application_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_is_admin"() RETURNS boolean
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN (SELECT admin FROM internal.additional_user_information WHERE id = (SELECT auth.uid()));
END;
$$;


ALTER FUNCTION "internal"."get_is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_own_business_unit_id"() RETURNS bigint
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN(SELECT business_unit_id FROM internal.additional_user_information WHERE id = (SELECT auth.uid()));
END
$$;


ALTER FUNCTION "internal"."get_own_business_unit_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_product_category_ids_downwards"("category_id" bigint, "include_own" boolean, "bypass_accessibility" boolean, "accessible_product_category_ids" bigint[]) RETURNS TABLE("id" bigint)
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE parent_recursion AS
  (
    SELECT pc.id as pc_id
    FROM internal.product_categories pc
    WHERE pc.id = category_id

    UNION ALL      

    SELECT pc.id 
    FROM parent_recursion, internal.product_categories pc
    WHERE parent_recursion.pc_id = pc.parent_id
  )
  SELECT pc_id FROM parent_recursion
  WHERE (bypass_accessibility OR (pc_id in (SELECT unnest(accessible_product_category_ids))))
  AND (include_own OR pc_id != category_id);
END;
$$;


ALTER FUNCTION "internal"."get_product_category_ids_downwards"("category_id" bigint, "include_own" boolean, "bypass_accessibility" boolean, "accessible_product_category_ids" bigint[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_product_category_path"("category_id" bigint, "accessible_product_category_ids" bigint[]) RETURNS "text"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  result_path text;
BEGIN
  WITH RECURSIVE parent_recursion AS
  (
    SELECT pc.id, pc.name, pc.parent_id, CAST(pc.name AS text) AS path
    FROM internal.product_categories pc
    WHERE pc.id = category_id AND pc.id IN (SELECT unnest(accessible_product_category_ids))    

    UNION ALL      

    SELECT pc.id, pc.name, pc.parent_id, CONCAT(pc.name, '/', pr.path) AS path
    FROM internal.product_categories pc
    INNER JOIN parent_recursion pr ON pc.id = pr.parent_id
  )
  SELECT path INTO result_path
  FROM parent_recursion
  WHERE parent_id IS NULL
  LIMIT 1;

  RETURN result_path;
END;
$$;


ALTER FUNCTION "internal"."get_product_category_path"("category_id" bigint, "accessible_product_category_ids" bigint[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_sindri_folder_ids_downwards"("folder_id" bigint, "include_own" boolean, "bypass_accessibility" boolean, "accessible_sindri_folder_ids" bigint[]) RETURNS TABLE("id" bigint)
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE parent_recursion AS
  (
    SELECT sf.id as sf_id
    FROM internal.sindri_folders sf
    WHERE sf.id = folder_id

    UNION ALL      

    SELECT sf.id 
    FROM parent_recursion, internal.sindri_folders sf
    WHERE parent_recursion.sf_id = sf.parent_id
  )
  SELECT sf_id FROM parent_recursion
  WHERE (bypass_accessibility OR (sf_id in (SELECT unnest(accessible_sindri_folder_ids))))
  AND (include_own OR sf_id != folder_id);
END;
$$;


ALTER FUNCTION "internal"."get_sindri_folder_ids_downwards"("folder_id" bigint, "include_own" boolean, "bypass_accessibility" boolean, "accessible_sindri_folder_ids" bigint[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."get_sindri_folder_path"("folder_id" bigint, "accessible_sindri_folder_ids" bigint[]) RETURNS "text"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
DECLARE
  result_path text;
BEGIN
  WITH RECURSIVE parent_recursion AS
  (
    SELECT sf.id, sf.name, sf.parent_id, CAST(sf.name AS text) AS path
    FROM internal.sindri_folders sf
    WHERE sf.id = folder_id AND sf.id IN (SELECT unnest(accessible_sindri_folder_ids))    

    UNION ALL      

    SELECT sf.id, sf.name, sf.parent_id, CONCAT(sf.name, '/', pr.path) AS path
    FROM internal.sindri_folders sf
    INNER JOIN parent_recursion pr ON sf.id = pr.parent_id
  )
  SELECT path INTO result_path
  FROM parent_recursion
  WHERE parent_id IS NULL
  LIMIT 1;

  RETURN result_path;
END;
$$;


ALTER FUNCTION "internal"."get_sindri_folder_path"("folder_id" bigint, "accessible_sindri_folder_ids" bigint[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."handle_application_version_deleted"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  PERFORM internal.delete_storage_file(OLD.file_key);
  RETURN OLD;
END;
$$;


ALTER FUNCTION "internal"."handle_application_version_deleted"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."handle_application_version_file_key_updated"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  PERFORM internal.delete_storage_file(OLD.file_key);
  RETURN NEW;
END;
$$;


ALTER FUNCTION "internal"."handle_application_version_file_key_updated"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."handle_product_browser_image_key_updated"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  PERFORM internal.delete_storage_file(OLD.browser_image_key);
  RETURN NEW;
END;
$$;


ALTER FUNCTION "internal"."handle_product_browser_image_key_updated"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."handle_product_category_created"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  INSERT INTO internal.product_categories_access(business_unit_id, product_category_id)
  SELECT bu.id, new.id 
  FROM (SELECT internal.get_business_unit_ids_upwards(true)) AS bu(id);
  RETURN NEW;
END;
$$;


ALTER FUNCTION "internal"."handle_product_category_created"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."handle_product_deleted"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  PERFORM internal.delete_storage_file(OLD.shelf_image_key);
  PERFORM internal.delete_storage_file(OLD.browser_image_key);
  RETURN OLD;
END;
$$;


ALTER FUNCTION "internal"."handle_product_deleted"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."handle_product_shelf_image_key_updated"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  PERFORM internal.delete_storage_file(OLD.shelf_image_key);
  RETURN NEW;
END;
$$;


ALTER FUNCTION "internal"."handle_product_shelf_image_key_updated"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."handle_sindri_folder_created"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  INSERT INTO internal.sindri_folders_access(business_unit_id, sindri_folder_id)
  SELECT bu.id, new.id 
  FROM (SELECT internal.get_business_unit_ids_upwards(true)) AS bu(id);
  RETURN NEW;
END;
$$;


ALTER FUNCTION "internal"."handle_sindri_folder_created"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."handle_storage_object_deleted"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  if(OLD.bucket_id = 'product_images') then
    if (OLD.name ~~ '%shelf%') then
      UPDATE internal.products SET shelf_image_key = null, updated_at = now() WHERE shelf_image_key = OLD.bucket_id || '/' || OLD.name;
    end if;
    if (OLD.name ~~ '%browser%') then
      UPDATE internal.products SET browser_image_key = null, updated_at = now() WHERE browser_image_key = OLD.bucket_id || '/' || OLD.name;
    end if;
  end if;
  if (OLD.bucket_id = 'version_files') then
    UPDATE internal.application_versions SET file_key = null WHERE file_key = OLD.bucket_id || '/' || OLD.name;
  end if;
  if (OLD.bucket_id = 'study_infos') then
    UPDATE internal.studies SET file_key = null, updated_at = now() WHERE file_key = OLD.bucket_id || '/' || OLD.name;
  end if;
  if (OLD.bucket_id = 'participant_files') then
    UPDATE internal.study_participants SET file_key = null WHERE file_key = OLD.bucket_id || '/' || OLD.name;
  end if;
  if (OLD.bucket_id = 'environment_images') then
    UPDATE internal.study_environments SET file_key = null WHERE file_key = OLD.bucket_id || '/' || OLD.name;
  end if;
  RETURN OLD;
END;
$$;


ALTER FUNCTION "internal"."handle_storage_object_deleted"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."handle_study_created"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  INSERT INTO internal.studies_access(business_unit_id, study_id)
  SELECT bu.id, new.id 
  FROM (SELECT internal.get_business_unit_ids_upwards(true)) AS bu(id);
  RETURN NEW;
END;
$$;


ALTER FUNCTION "internal"."handle_study_created"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."handle_study_deleted"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  PERFORM internal.delete_storage_file(OLD.file_key);
  RETURN OLD;
END;
$$;


ALTER FUNCTION "internal"."handle_study_deleted"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."handle_study_environment_deleted"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  PERFORM internal.delete_storage_file(OLD.file_key);
  RETURN OLD;
END;
$$;


ALTER FUNCTION "internal"."handle_study_environment_deleted"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."handle_study_environment_file_key_updated"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  PERFORM internal.delete_storage_file(OLD.file_key);
  RETURN NEW;
END;
$$;


ALTER FUNCTION "internal"."handle_study_environment_file_key_updated"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."handle_study_file_key_updated"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  PERFORM internal.delete_storage_file(OLD.file_key);
  RETURN NEW;
END;
$$;


ALTER FUNCTION "internal"."handle_study_file_key_updated"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."handle_study_participant_deleted"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  PERFORM internal.delete_storage_file(OLD.file_key);
  RETURN OLD;
END;
$$;


ALTER FUNCTION "internal"."handle_study_participant_deleted"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."handle_study_participant_file_key_updated"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO ''
    AS $$
BEGIN
  PERFORM internal.delete_storage_file(OLD.file_key);
  RETURN NEW;
END;
$$;


ALTER FUNCTION "internal"."handle_study_participant_file_key_updated"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "internal"."handle_user_created"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  name text;
BEGIN
  INSERT INTO internal.additional_user_information (id, admin)
  VALUES (new.id, false);
  RETURN NEW;
END;
$$;


ALTER FUNCTION "internal"."handle_user_created"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "internal"."active_users" (
    "user_id" "uuid" NOT NULL,
    "business_unit_id" bigint NOT NULL,
    "application_name" "text" NOT NULL,
    "last_active_at" timestamp without time zone,
    "last_computer_hash" "text"
);


ALTER TABLE "internal"."active_users" OWNER TO "postgres";


COMMENT ON TABLE "internal"."active_users" IS 'Contains all users and their last active ping times in the different applications.';



CREATE TABLE IF NOT EXISTS "internal"."additional_user_information" (
    "id" "uuid" NOT NULL,
    "business_unit_id" bigint,
    "admin" boolean DEFAULT false NOT NULL
);


ALTER TABLE "internal"."additional_user_information" OWNER TO "postgres";


COMMENT ON TABLE "internal"."additional_user_information" IS 'Contains additional user data like the business unit and if the user is an admin.';



CREATE TABLE IF NOT EXISTS "internal"."application_versions" (
    "id" bigint NOT NULL,
    "version" "text" NOT NULL,
    "created_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    "file_key" "text",
    "application_name" "text" NOT NULL
);


ALTER TABLE "internal"."application_versions" OWNER TO "postgres";


COMMENT ON TABLE "internal"."application_versions" IS 'Contains all uploaded release and beta versions of the different applications.';



ALTER TABLE "internal"."application_versions" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "internal"."application_version_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "internal"."applications" (
    "name" "text" NOT NULL,
    "beta_version_id" bigint,
    "release_version_id" bigint
);


ALTER TABLE "internal"."applications" OWNER TO "postgres";


COMMENT ON TABLE "internal"."applications" IS 'Contains all the applications that can be pinged.';



CREATE TABLE IF NOT EXISTS "internal"."business_units" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "phone" "text",
    "website" "text",
    "email" "text",
    "parent_id" bigint
);


ALTER TABLE "internal"."business_units" OWNER TO "postgres";


COMMENT ON TABLE "internal"."business_units" IS 'Contains the business units that organize users in nested groups. All access is handled on business unit level.';



ALTER TABLE "internal"."business_units" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "internal"."business_units_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "internal"."max_concurrent_connections" (
    "id" bigint NOT NULL,
    "business_unit_id" bigint NOT NULL,
    "application_name" "text" NOT NULL,
    "max_connections" bigint DEFAULT '0'::bigint NOT NULL
);


ALTER TABLE "internal"."max_concurrent_connections" OWNER TO "postgres";


COMMENT ON TABLE "internal"."max_concurrent_connections" IS 'Contains the maximum number of concurrent logins of business units in applications';



ALTER TABLE "internal"."max_concurrent_connections" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "internal"."max_logins_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "internal"."product_categories" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "parent_id" bigint
);


ALTER TABLE "internal"."product_categories" OWNER TO "postgres";


COMMENT ON TABLE "internal"."product_categories" IS 'Contains nested product categories to organize products.';



CREATE TABLE IF NOT EXISTS "internal"."product_categories_access" (
    "business_unit_id" bigint NOT NULL,
    "product_category_id" bigint NOT NULL,
    "access_level" "internal"."access_level" DEFAULT 'write'::"internal"."access_level" NOT NULL
);


ALTER TABLE "internal"."product_categories_access" OWNER TO "postgres";


COMMENT ON TABLE "internal"."product_categories_access" IS 'Contains a connection between business units and product categories in order to handle the access.';



ALTER TABLE "internal"."product_categories_access" ALTER COLUMN "business_unit_id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "internal"."product_categories_access_business_unit_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "internal"."product_categories_access" ALTER COLUMN "product_category_id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "internal"."product_categories_access_product_category_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "internal"."product_categories" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "internal"."product_categories_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "internal"."products" (
    "id" bigint NOT NULL,
    "category_id" bigint NOT NULL,
    "custom_id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "price_tag_text" "text",
    "brand" "text",
    "manufacturer" "text",
    "quantity" "text",
    "note" "text",
    "width" real DEFAULT '0.1'::real NOT NULL,
    "height" real DEFAULT '0.1'::real NOT NULL,
    "depth" real DEFAULT '0.1'::real NOT NULL,
    "shelf_image_key" "text",
    "browser_image_key" "text",
    "created_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    "price" double precision
);


ALTER TABLE "internal"."products" OWNER TO "postgres";


COMMENT ON TABLE "internal"."products" IS 'Contains product information.';



ALTER TABLE "internal"."products" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "internal"."products_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "internal"."study_scenarios" (
    "id" bigint NOT NULL,
    "study_id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "environment_name" "text",
    "optional" boolean DEFAULT false NOT NULL,
    "order_in_study" bigint DEFAULT '0'::bigint NOT NULL
);


ALTER TABLE "internal"."study_scenarios" OWNER TO "postgres";


COMMENT ON TABLE "internal"."study_scenarios" IS 'Represents an unchangeable virtual environment inside a study.';



ALTER TABLE "internal"."study_scenarios" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "internal"."scenario_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "internal"."sindri_folders" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "parent_id" bigint
);


ALTER TABLE "internal"."sindri_folders" OWNER TO "postgres";


COMMENT ON TABLE "internal"."sindri_folders" IS 'Contains a nested structure for organizing sindri saves.';



ALTER TABLE "internal"."sindri_folders" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "internal"."sindri_folder_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "internal"."sindri_folders_access" (
    "business_unit_id" bigint NOT NULL,
    "sindri_folder_id" bigint NOT NULL,
    "access_level" "internal"."access_level" DEFAULT 'write'::"internal"."access_level" NOT NULL
);


ALTER TABLE "internal"."sindri_folders_access" OWNER TO "postgres";


COMMENT ON TABLE "internal"."sindri_folders_access" IS 'Contains a connection between business units and sindri folder in order to handle the access.';



ALTER TABLE "internal"."sindri_folders_access" ALTER COLUMN "business_unit_id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "internal"."sindri_folders_access_business_unit_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "internal"."sindri_folders_access" ALTER COLUMN "sindri_folder_id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "internal"."sindri_folders_access_sindri_folder_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "internal"."sindri_saves" (
    "id" bigint NOT NULL,
    "folder_id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    "content" "text"
);


ALTER TABLE "internal"."sindri_saves" OWNER TO "postgres";


COMMENT ON TABLE "internal"."sindri_saves" IS 'Contains all saves created from sindri.';



ALTER TABLE "internal"."sindri_saves" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "internal"."sindri_save_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "internal"."studies" (
    "id" bigint NOT NULL,
    "created_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "number_test_locations" bigint DEFAULT '1'::bigint NOT NULL,
    "file_key" "text",
    "status" "internal"."study_status" DEFAULT 'draft'::"internal"."study_status" NOT NULL,
    "updated_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    "number_participants" bigint DEFAULT '0'::bigint NOT NULL
);


ALTER TABLE "internal"."studies" OWNER TO "postgres";


COMMENT ON TABLE "internal"."studies" IS 'Contains base information about the mimir studies.';



CREATE TABLE IF NOT EXISTS "internal"."studies_access" (
    "business_unit_id" bigint NOT NULL,
    "study_id" bigint NOT NULL,
    "access_level" "internal"."access_level" DEFAULT 'write'::"internal"."access_level" NOT NULL
);


ALTER TABLE "internal"."studies_access" OWNER TO "postgres";


COMMENT ON TABLE "internal"."studies_access" IS 'Contains a connection between business units and studies in order to handle the access.';



ALTER TABLE "internal"."studies" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "internal"."studies_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "internal"."studies_access" ALTER COLUMN "business_unit_id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "internal"."study_access_business_unit_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "internal"."study_computers" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "location" "text",
    "cpu" "text",
    "gpu" "text",
    "identifier" "text",
    "participant_id_min" bigint,
    "participant_id_max" bigint,
    "study_id" bigint
);


ALTER TABLE "internal"."study_computers" OWNER TO "postgres";


COMMENT ON TABLE "internal"."study_computers" IS 'Contains information about all the vr insight computers that are used for participant testing.';



ALTER TABLE "internal"."study_computers" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "internal"."study_computers_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "internal"."study_environments" (
    "name" "text" NOT NULL,
    "description" "text",
    "width" double precision DEFAULT '0'::double precision NOT NULL,
    "height" double precision DEFAULT '0'::double precision NOT NULL,
    "depth" double precision DEFAULT '0'::double precision NOT NULL,
    "center_x" double precision DEFAULT '0'::double precision NOT NULL,
    "center_y" double precision DEFAULT '0'::double precision NOT NULL,
    "center_z" double precision DEFAULT '0'::double precision NOT NULL,
    "file_key" "text"
);


ALTER TABLE "internal"."study_environments" OWNER TO "postgres";


COMMENT ON TABLE "internal"."study_environments" IS 'Represents an environment type that can be used as a base for scenarios..';



CREATE TABLE IF NOT EXISTS "internal"."study_monads" (
    "id" bigint NOT NULL,
    "study_id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "participant_goal" bigint,
    "distributions" "json",
    "scenario_orders" "json",
    "order_in_study" bigint DEFAULT '0'::bigint NOT NULL
);


ALTER TABLE "internal"."study_monads" OWNER TO "postgres";


COMMENT ON TABLE "internal"."study_monads" IS 'Represents an independent group of participants for a study that sees certain scenarios and tasks.';



ALTER TABLE "internal"."study_monads" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "internal"."study_monad_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "internal"."study_participants" (
    "custom_id" "text" NOT NULL,
    "study_id" bigint NOT NULL,
    "monad_id" bigint NOT NULL,
    "recorded_by" bigint,
    "fixation_data_valid" boolean DEFAULT false NOT NULL,
    "position_data_valid" boolean DEFAULT false NOT NULL,
    "file_key" "text",
    "properties" "json",
    "finished_scenario_ids" "json",
    "finished_task_ids" "json",
    "created_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    "all_scenarios_finished" boolean DEFAULT false NOT NULL,
    "all_tasks_finished" boolean DEFAULT false NOT NULL,
    "id" bigint NOT NULL
);


ALTER TABLE "internal"."study_participants" OWNER TO "postgres";


COMMENT ON TABLE "internal"."study_participants" IS 'Contains information about the tested participants in their study including a data file.';



ALTER TABLE "internal"."study_participants" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "internal"."study_participants_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "internal"."study_tasks" (
    "id" bigint NOT NULL,
    "study_id" bigint NOT NULL,
    "scenario_id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "task_text" "text",
    "start_position_x" double precision DEFAULT '0'::double precision NOT NULL,
    "start_position_y" double precision DEFAULT '0'::double precision NOT NULL,
    "start_position_z" double precision DEFAULT '0'::double precision NOT NULL,
    "product_transport" "internal"."product_transport" DEFAULT 'shopping_basket'::"internal"."product_transport" NOT NULL,
    "buying_restriction" "internal"."buying_restriction" DEFAULT 'purchases'::"internal"."buying_restriction" NOT NULL,
    "buying_limit" double precision DEFAULT '0'::double precision NOT NULL,
    "blind_limit" boolean DEFAULT false NOT NULL,
    "teleport_range" bigint DEFAULT '0'::bigint NOT NULL,
    "set_time_stamp_button" boolean DEFAULT false NOT NULL,
    "order_in_scenario" bigint DEFAULT '0'::bigint NOT NULL,
    "start_rotation" double precision DEFAULT '0'::double precision NOT NULL,
    "optional" boolean DEFAULT false NOT NULL
);


ALTER TABLE "internal"."study_tasks" OWNER TO "postgres";


COMMENT ON TABLE "internal"."study_tasks" IS 'Represents shopping tasks inside a certain scenario.';



ALTER TABLE "internal"."study_tasks" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "internal"."study_tasks_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "internal"."user_application_permissions" (
    "id" bigint NOT NULL,
    "application_name" "text" NOT NULL,
    "permission_json" "json",
    "user_id" "uuid" NOT NULL
);


ALTER TABLE "internal"."user_application_permissions" OWNER TO "postgres";


COMMENT ON TABLE "internal"."user_application_permissions" IS 'Contains all additional permissions for the applications on user level';



ALTER TABLE "internal"."user_application_permissions" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "internal"."user_application_permissions_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE ONLY "internal"."active_users"
    ADD CONSTRAINT "active_users_pkey" PRIMARY KEY ("user_id", "application_name");



ALTER TABLE ONLY "internal"."additional_user_information"
    ADD CONSTRAINT "additional_user_information_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."application_versions"
    ADD CONSTRAINT "application_version_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."applications"
    ADD CONSTRAINT "applications_pkey" PRIMARY KEY ("name");



ALTER TABLE ONLY "internal"."business_units"
    ADD CONSTRAINT "business_units_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."max_concurrent_connections"
    ADD CONSTRAINT "max_logins_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."product_categories_access"
    ADD CONSTRAINT "product_categories_access_pkey" PRIMARY KEY ("business_unit_id", "product_category_id");



ALTER TABLE ONLY "internal"."product_categories"
    ADD CONSTRAINT "product_categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."study_scenarios"
    ADD CONSTRAINT "scenario_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."sindri_folders"
    ADD CONSTRAINT "sindri_folder_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."sindri_folders_access"
    ADD CONSTRAINT "sindri_folders_access_pkey" PRIMARY KEY ("business_unit_id", "sindri_folder_id");



ALTER TABLE ONLY "internal"."sindri_saves"
    ADD CONSTRAINT "sindri_save_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."studies_access"
    ADD CONSTRAINT "study_access_pkey" PRIMARY KEY ("business_unit_id", "study_id");



ALTER TABLE ONLY "internal"."study_computers"
    ADD CONSTRAINT "study_computers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."study_environments"
    ADD CONSTRAINT "study_environments_pkey" PRIMARY KEY ("name");



ALTER TABLE ONLY "internal"."study_monads"
    ADD CONSTRAINT "study_monad_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."study_participants"
    ADD CONSTRAINT "study_participants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."studies"
    ADD CONSTRAINT "study_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."study_tasks"
    ADD CONSTRAINT "study_tasks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "internal"."user_application_permissions"
    ADD CONSTRAINT "user_application_permissions_pkey" PRIMARY KEY ("id");



CREATE INDEX "active_users_application_name_idx" ON "internal"."active_users" USING "btree" ("application_name");



CREATE INDEX "active_users_business_unit_id_idx" ON "internal"."active_users" USING "btree" ("business_unit_id");



CREATE INDEX "additional_user_information_business_unit_idx" ON "internal"."additional_user_information" USING "btree" ("business_unit_id");



CREATE INDEX "application_versions_application_name_idx" ON "internal"."application_versions" USING "btree" ("application_name");



CREATE INDEX "applications_beta_version_id_idx" ON "internal"."applications" USING "btree" ("beta_version_id");



CREATE INDEX "applications_release_version_id_idx" ON "internal"."applications" USING "btree" ("release_version_id");



CREATE INDEX "business_units_parent_id_idx" ON "internal"."business_units" USING "btree" ("parent_id");



CREATE INDEX "max_concurrent_connections_application_name_idx" ON "internal"."max_concurrent_connections" USING "btree" ("application_name");



CREATE INDEX "max_concurrent_connections_business_unit_id_idx" ON "internal"."max_concurrent_connections" USING "btree" ("business_unit_id");



CREATE INDEX "product_categories_access_product_category_id_idx" ON "internal"."product_categories_access" USING "btree" ("product_category_id");



CREATE INDEX "product_categories_parent_id_idx" ON "internal"."product_categories" USING "btree" ("parent_id");



CREATE INDEX "products_category_id_idx" ON "internal"."products" USING "btree" ("category_id");



CREATE INDEX "sindri_folders_access_sindri_folder_id_idx" ON "internal"."sindri_folders_access" USING "btree" ("sindri_folder_id");



CREATE INDEX "sindri_folders_parent_id_idx" ON "internal"."sindri_folders" USING "btree" ("parent_id");



CREATE INDEX "sindri_saves_folder_id_idx" ON "internal"."sindri_saves" USING "btree" ("folder_id");



CREATE INDEX "studies_access_study_id_idx" ON "internal"."studies_access" USING "btree" ("study_id");



CREATE INDEX "study_computers_study_id_idx" ON "internal"."study_computers" USING "btree" ("study_id");



CREATE INDEX "study_monads_study_id_idx" ON "internal"."study_monads" USING "btree" ("study_id");



CREATE INDEX "study_participants_monad_id_idx" ON "internal"."study_participants" USING "btree" ("monad_id");



CREATE INDEX "study_participants_recorded_by_idx" ON "internal"."study_participants" USING "btree" ("recorded_by");



CREATE INDEX "study_participants_study_id_idx" ON "internal"."study_participants" USING "btree" ("study_id");



CREATE INDEX "study_scenarios_environment_id_idx" ON "internal"."study_scenarios" USING "btree" ("environment_name");



CREATE INDEX "study_scenarios_study_id_idx" ON "internal"."study_scenarios" USING "btree" ("study_id");



CREATE INDEX "study_tasks_scenario_id_idx" ON "internal"."study_tasks" USING "btree" ("scenario_id");



CREATE INDEX "study_tasks_study_id_idx" ON "internal"."study_tasks" USING "btree" ("study_id");



CREATE INDEX "user_application_permissions_application_name_idx" ON "internal"."user_application_permissions" USING "btree" ("application_name");



CREATE INDEX "user_application_permissions_user_id_idx" ON "internal"."user_application_permissions" USING "btree" ("user_id");



CREATE OR REPLACE TRIGGER "on_application_version_deleted" AFTER DELETE ON "internal"."application_versions" FOR EACH ROW EXECUTE FUNCTION "internal"."handle_application_version_deleted"();



CREATE OR REPLACE TRIGGER "on_application_version_file_key_updated" AFTER UPDATE OF "file_key" ON "internal"."application_versions" FOR EACH ROW EXECUTE FUNCTION "internal"."handle_application_version_file_key_updated"();



CREATE OR REPLACE TRIGGER "on_product_browser_image_key_updated" AFTER UPDATE OF "browser_image_key" ON "internal"."products" FOR EACH ROW EXECUTE FUNCTION "internal"."handle_product_browser_image_key_updated"();



CREATE OR REPLACE TRIGGER "on_product_category_created" AFTER INSERT ON "internal"."product_categories" FOR EACH ROW EXECUTE FUNCTION "internal"."handle_product_category_created"();



CREATE OR REPLACE TRIGGER "on_product_deleted" AFTER DELETE ON "internal"."products" FOR EACH ROW EXECUTE FUNCTION "internal"."handle_product_deleted"();



CREATE OR REPLACE TRIGGER "on_product_shelf_image_key_updated" AFTER UPDATE OF "shelf_image_key" ON "internal"."products" FOR EACH ROW EXECUTE FUNCTION "internal"."handle_product_shelf_image_key_updated"();



CREATE OR REPLACE TRIGGER "on_sindri_folder_created" AFTER INSERT ON "internal"."sindri_folders" FOR EACH ROW EXECUTE FUNCTION "internal"."handle_sindri_folder_created"();



CREATE OR REPLACE TRIGGER "on_study_created" AFTER INSERT ON "internal"."studies" FOR EACH ROW EXECUTE FUNCTION "internal"."handle_study_created"();



CREATE OR REPLACE TRIGGER "on_study_deleted" AFTER DELETE ON "internal"."studies" FOR EACH ROW EXECUTE FUNCTION "internal"."handle_study_deleted"();



CREATE OR REPLACE TRIGGER "on_study_environment_deleted" AFTER DELETE ON "internal"."study_environments" FOR EACH ROW EXECUTE FUNCTION "internal"."handle_study_environment_deleted"();



CREATE OR REPLACE TRIGGER "on_study_environment_file_key_updated" AFTER UPDATE OF "file_key" ON "internal"."study_environments" FOR EACH ROW EXECUTE FUNCTION "internal"."handle_study_environment_file_key_updated"();



CREATE OR REPLACE TRIGGER "on_study_file_key_updated" AFTER UPDATE OF "file_key" ON "internal"."studies" FOR EACH ROW EXECUTE FUNCTION "internal"."handle_study_file_key_updated"();



CREATE OR REPLACE TRIGGER "on_study_participant_deleted" AFTER DELETE ON "internal"."study_participants" FOR EACH ROW EXECUTE FUNCTION "internal"."handle_study_participant_deleted"();



CREATE OR REPLACE TRIGGER "on_study_participant_file_key_updated" AFTER UPDATE OF "file_key" ON "internal"."study_participants" FOR EACH ROW EXECUTE FUNCTION "internal"."handle_study_participant_file_key_updated"();



ALTER TABLE ONLY "internal"."active_users"
    ADD CONSTRAINT "active_users_application_name_fkey" FOREIGN KEY ("application_name") REFERENCES "internal"."applications"("name") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."active_users"
    ADD CONSTRAINT "active_users_business_unit_id_fkey" FOREIGN KEY ("business_unit_id") REFERENCES "internal"."business_units"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."active_users"
    ADD CONSTRAINT "active_users_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."additional_user_information"
    ADD CONSTRAINT "additional_user_information_business_unit_fkey" FOREIGN KEY ("business_unit_id") REFERENCES "internal"."business_units"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "internal"."additional_user_information"
    ADD CONSTRAINT "additional_user_information_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."application_versions"
    ADD CONSTRAINT "application_versions_application_fkey" FOREIGN KEY ("application_name") REFERENCES "internal"."applications"("name") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."applications"
    ADD CONSTRAINT "applications_beta_version_fkey" FOREIGN KEY ("beta_version_id") REFERENCES "internal"."application_versions"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "internal"."applications"
    ADD CONSTRAINT "applications_release_version_fkey" FOREIGN KEY ("release_version_id") REFERENCES "internal"."application_versions"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "internal"."business_units"
    ADD CONSTRAINT "business_units_parent_fkey" FOREIGN KEY ("parent_id") REFERENCES "internal"."business_units"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."max_concurrent_connections"
    ADD CONSTRAINT "max_logins_application_name_fkey" FOREIGN KEY ("application_name") REFERENCES "internal"."applications"("name") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."max_concurrent_connections"
    ADD CONSTRAINT "max_logins_business_unit_id_fkey" FOREIGN KEY ("business_unit_id") REFERENCES "internal"."business_units"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."product_categories_access"
    ADD CONSTRAINT "product_categories_access_business_unit_id_fkey" FOREIGN KEY ("business_unit_id") REFERENCES "internal"."business_units"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."product_categories_access"
    ADD CONSTRAINT "product_categories_access_product_category_id_fkey" FOREIGN KEY ("product_category_id") REFERENCES "internal"."product_categories"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."product_categories"
    ADD CONSTRAINT "product_categories_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "internal"."product_categories"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "internal"."products"
    ADD CONSTRAINT "products_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "internal"."product_categories"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."study_scenarios"
    ADD CONSTRAINT "scenario_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "internal"."studies"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."sindri_folders"
    ADD CONSTRAINT "sindri_folder_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "internal"."sindri_folders"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "internal"."sindri_folders_access"
    ADD CONSTRAINT "sindri_folders_access_business_unit_id_fkey" FOREIGN KEY ("business_unit_id") REFERENCES "internal"."business_units"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."sindri_folders_access"
    ADD CONSTRAINT "sindri_folders_access_sindri_folder_id_fkey" FOREIGN KEY ("sindri_folder_id") REFERENCES "internal"."sindri_folders"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."sindri_saves"
    ADD CONSTRAINT "sindri_save_folder_id_fkey" FOREIGN KEY ("folder_id") REFERENCES "internal"."sindri_folders"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."studies_access"
    ADD CONSTRAINT "study_access_business_unit_id_fkey" FOREIGN KEY ("business_unit_id") REFERENCES "internal"."business_units"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."studies_access"
    ADD CONSTRAINT "study_access_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "internal"."studies"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."study_computers"
    ADD CONSTRAINT "study_computers_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "internal"."studies"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "internal"."study_monads"
    ADD CONSTRAINT "study_monad_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "internal"."studies"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."study_participants"
    ADD CONSTRAINT "study_participant_monad_id_fkey" FOREIGN KEY ("monad_id") REFERENCES "internal"."study_monads"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."study_participants"
    ADD CONSTRAINT "study_participants_recorded_by_fkey" FOREIGN KEY ("recorded_by") REFERENCES "internal"."study_computers"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "internal"."study_participants"
    ADD CONSTRAINT "study_participants_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "internal"."studies"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "internal"."study_scenarios"
    ADD CONSTRAINT "study_scenarios_environment_name_fkey" FOREIGN KEY ("environment_name") REFERENCES "internal"."study_environments"("name") ON UPDATE CASCADE;



ALTER TABLE ONLY "internal"."study_tasks"
    ADD CONSTRAINT "study_tasks_scenario_id_fkey" FOREIGN KEY ("scenario_id") REFERENCES "internal"."study_scenarios"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."study_tasks"
    ADD CONSTRAINT "study_tasks_study_id_fkey" FOREIGN KEY ("study_id") REFERENCES "internal"."studies"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."user_application_permissions"
    ADD CONSTRAINT "user_application_permissions_application_name_fkey" FOREIGN KEY ("application_name") REFERENCES "internal"."applications"("name") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "internal"."user_application_permissions"
    ADD CONSTRAINT "user_application_permissions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE "internal"."active_users" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "internal"."additional_user_information" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "internal"."application_versions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "internal"."applications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "internal"."business_units" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "internal"."max_concurrent_connections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "internal"."product_categories" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "internal"."product_categories_access" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "internal"."products" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "read_write_active_users" ON "internal"."active_users" TO "authenticated" USING (true);



CREATE POLICY "read_write_additional_user_information" ON "internal"."additional_user_information" TO "authenticated" USING (true);



CREATE POLICY "read_write_application_versions" ON "internal"."application_versions" TO "authenticated" USING (true);



CREATE POLICY "read_write_applications" ON "internal"."applications" TO "authenticated" USING (true);



CREATE POLICY "read_write_business_units" ON "internal"."business_units" TO "authenticated" USING (true);



CREATE POLICY "read_write_max_concurrent_connections" ON "internal"."max_concurrent_connections" TO "authenticated" USING (true);



CREATE POLICY "read_write_product_categories" ON "internal"."product_categories" TO "authenticated" USING (true);



CREATE POLICY "read_write_product_categories_access" ON "internal"."product_categories_access" TO "authenticated" USING (true);



CREATE POLICY "read_write_products" ON "internal"."products" TO "authenticated" USING (true);



CREATE POLICY "read_write_sindri_folders" ON "internal"."sindri_folders" TO "authenticated" USING (true);



CREATE POLICY "read_write_sindri_folders_access" ON "internal"."sindri_folders_access" TO "authenticated" USING (true);



CREATE POLICY "read_write_sindri_saves" ON "internal"."sindri_saves" TO "authenticated" USING (true);



CREATE POLICY "read_write_studies" ON "internal"."studies" TO "authenticated" USING (true);



CREATE POLICY "read_write_studies_access" ON "internal"."studies_access" TO "authenticated" USING (true);



CREATE POLICY "read_write_study_computers" ON "internal"."study_computers" TO "authenticated" USING (true);



CREATE POLICY "read_write_study_environments" ON "internal"."study_environments" TO "authenticated" USING (true);



CREATE POLICY "read_write_study_monads" ON "internal"."study_monads" TO "authenticated" USING (true);



CREATE POLICY "read_write_study_participants" ON "internal"."study_participants" TO "authenticated" USING (true);



CREATE POLICY "read_write_study_scenarios" ON "internal"."study_scenarios" TO "authenticated" USING (true);



CREATE POLICY "read_write_study_tasks" ON "internal"."study_tasks" TO "authenticated" USING (true);



CREATE POLICY "read_write_user_application_permissions" ON "internal"."user_application_permissions" TO "authenticated" USING (true);



ALTER TABLE "internal"."sindri_folders" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "internal"."sindri_folders_access" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "internal"."sindri_saves" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "internal"."studies" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "internal"."studies_access" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "internal"."study_computers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "internal"."study_environments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "internal"."study_monads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "internal"."study_participants" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "internal"."study_scenarios" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "internal"."study_tasks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "internal"."user_application_permissions" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "api" TO "anon";
GRANT USAGE ON SCHEMA "api" TO "authenticated";
GRANT USAGE ON SCHEMA "api" TO "service_role";



GRANT USAGE ON SCHEMA "internal" TO "anon";
GRANT USAGE ON SCHEMA "internal" TO "authenticated";
GRANT USAGE ON SCHEMA "internal" TO "service_role";






GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";























































































































































































GRANT ALL ON FUNCTION "internal"."delete_storage_file"("file_key" "text") TO "anon";
GRANT ALL ON FUNCTION "internal"."delete_storage_file"("file_key" "text") TO "authenticated";
GRANT ALL ON FUNCTION "internal"."delete_storage_file"("file_key" "text") TO "service_role";



GRANT ALL ON FUNCTION "internal"."get_accessible_product_category_ids"("write_only" boolean) TO "anon";
GRANT ALL ON FUNCTION "internal"."get_accessible_product_category_ids"("write_only" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "internal"."get_accessible_product_category_ids"("write_only" boolean) TO "service_role";



GRANT ALL ON FUNCTION "internal"."get_accessible_sindri_folder_ids"("write_only" boolean) TO "anon";
GRANT ALL ON FUNCTION "internal"."get_accessible_sindri_folder_ids"("write_only" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "internal"."get_accessible_sindri_folder_ids"("write_only" boolean) TO "service_role";



GRANT ALL ON FUNCTION "internal"."get_accessible_study_ids"("write_only" boolean) TO "anon";
GRANT ALL ON FUNCTION "internal"."get_accessible_study_ids"("write_only" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "internal"."get_accessible_study_ids"("write_only" boolean) TO "service_role";



GRANT ALL ON FUNCTION "internal"."get_business_unit_ids_downwards"("include_own" boolean) TO "anon";
GRANT ALL ON FUNCTION "internal"."get_business_unit_ids_downwards"("include_own" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "internal"."get_business_unit_ids_downwards"("include_own" boolean) TO "service_role";



GRANT ALL ON FUNCTION "internal"."get_business_unit_ids_upwards"("include_own" boolean) TO "anon";
GRANT ALL ON FUNCTION "internal"."get_business_unit_ids_upwards"("include_own" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "internal"."get_business_unit_ids_upwards"("include_own" boolean) TO "service_role";



GRANT ALL ON FUNCTION "internal"."get_category_id_parent_path"("category_id" bigint, "accessible_product_category_ids" bigint[], "include_own" boolean) TO "anon";
GRANT ALL ON FUNCTION "internal"."get_category_id_parent_path"("category_id" bigint, "accessible_product_category_ids" bigint[], "include_own" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "internal"."get_category_id_parent_path"("category_id" bigint, "accessible_product_category_ids" bigint[], "include_own" boolean) TO "service_role";



GRANT ALL ON FUNCTION "internal"."get_connection_defining_business_unit"("application_name" "text") TO "anon";
GRANT ALL ON FUNCTION "internal"."get_connection_defining_business_unit"("application_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "internal"."get_connection_defining_business_unit"("application_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "internal"."get_is_admin"() TO "anon";
GRANT ALL ON FUNCTION "internal"."get_is_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "internal"."get_is_admin"() TO "service_role";



GRANT ALL ON FUNCTION "internal"."get_own_business_unit_id"() TO "anon";
GRANT ALL ON FUNCTION "internal"."get_own_business_unit_id"() TO "authenticated";
GRANT ALL ON FUNCTION "internal"."get_own_business_unit_id"() TO "service_role";



GRANT ALL ON FUNCTION "internal"."get_product_category_ids_downwards"("category_id" bigint, "include_own" boolean, "bypass_accessibility" boolean, "accessible_product_category_ids" bigint[]) TO "anon";
GRANT ALL ON FUNCTION "internal"."get_product_category_ids_downwards"("category_id" bigint, "include_own" boolean, "bypass_accessibility" boolean, "accessible_product_category_ids" bigint[]) TO "authenticated";
GRANT ALL ON FUNCTION "internal"."get_product_category_ids_downwards"("category_id" bigint, "include_own" boolean, "bypass_accessibility" boolean, "accessible_product_category_ids" bigint[]) TO "service_role";



GRANT ALL ON FUNCTION "internal"."get_product_category_path"("category_id" bigint, "accessible_product_category_ids" bigint[]) TO "anon";
GRANT ALL ON FUNCTION "internal"."get_product_category_path"("category_id" bigint, "accessible_product_category_ids" bigint[]) TO "authenticated";
GRANT ALL ON FUNCTION "internal"."get_product_category_path"("category_id" bigint, "accessible_product_category_ids" bigint[]) TO "service_role";



GRANT ALL ON FUNCTION "internal"."get_sindri_folder_ids_downwards"("folder_id" bigint, "include_own" boolean, "bypass_accessibility" boolean, "accessible_sindri_folder_ids" bigint[]) TO "anon";
GRANT ALL ON FUNCTION "internal"."get_sindri_folder_ids_downwards"("folder_id" bigint, "include_own" boolean, "bypass_accessibility" boolean, "accessible_sindri_folder_ids" bigint[]) TO "authenticated";
GRANT ALL ON FUNCTION "internal"."get_sindri_folder_ids_downwards"("folder_id" bigint, "include_own" boolean, "bypass_accessibility" boolean, "accessible_sindri_folder_ids" bigint[]) TO "service_role";



GRANT ALL ON FUNCTION "internal"."get_sindri_folder_path"("folder_id" bigint, "accessible_sindri_folder_ids" bigint[]) TO "anon";
GRANT ALL ON FUNCTION "internal"."get_sindri_folder_path"("folder_id" bigint, "accessible_sindri_folder_ids" bigint[]) TO "authenticated";
GRANT ALL ON FUNCTION "internal"."get_sindri_folder_path"("folder_id" bigint, "accessible_sindri_folder_ids" bigint[]) TO "service_role";



GRANT ALL ON FUNCTION "internal"."handle_application_version_deleted"() TO "anon";
GRANT ALL ON FUNCTION "internal"."handle_application_version_deleted"() TO "authenticated";
GRANT ALL ON FUNCTION "internal"."handle_application_version_deleted"() TO "service_role";



GRANT ALL ON FUNCTION "internal"."handle_application_version_file_key_updated"() TO "anon";
GRANT ALL ON FUNCTION "internal"."handle_application_version_file_key_updated"() TO "authenticated";
GRANT ALL ON FUNCTION "internal"."handle_application_version_file_key_updated"() TO "service_role";



GRANT ALL ON FUNCTION "internal"."handle_product_browser_image_key_updated"() TO "anon";
GRANT ALL ON FUNCTION "internal"."handle_product_browser_image_key_updated"() TO "authenticated";
GRANT ALL ON FUNCTION "internal"."handle_product_browser_image_key_updated"() TO "service_role";



GRANT ALL ON FUNCTION "internal"."handle_product_category_created"() TO "anon";
GRANT ALL ON FUNCTION "internal"."handle_product_category_created"() TO "authenticated";
GRANT ALL ON FUNCTION "internal"."handle_product_category_created"() TO "service_role";



GRANT ALL ON FUNCTION "internal"."handle_product_deleted"() TO "anon";
GRANT ALL ON FUNCTION "internal"."handle_product_deleted"() TO "authenticated";
GRANT ALL ON FUNCTION "internal"."handle_product_deleted"() TO "service_role";



GRANT ALL ON FUNCTION "internal"."handle_product_shelf_image_key_updated"() TO "anon";
GRANT ALL ON FUNCTION "internal"."handle_product_shelf_image_key_updated"() TO "authenticated";
GRANT ALL ON FUNCTION "internal"."handle_product_shelf_image_key_updated"() TO "service_role";



GRANT ALL ON FUNCTION "internal"."handle_sindri_folder_created"() TO "anon";
GRANT ALL ON FUNCTION "internal"."handle_sindri_folder_created"() TO "authenticated";
GRANT ALL ON FUNCTION "internal"."handle_sindri_folder_created"() TO "service_role";



GRANT ALL ON FUNCTION "internal"."handle_storage_object_deleted"() TO "anon";
GRANT ALL ON FUNCTION "internal"."handle_storage_object_deleted"() TO "authenticated";
GRANT ALL ON FUNCTION "internal"."handle_storage_object_deleted"() TO "service_role";



GRANT ALL ON FUNCTION "internal"."handle_study_created"() TO "anon";
GRANT ALL ON FUNCTION "internal"."handle_study_created"() TO "authenticated";
GRANT ALL ON FUNCTION "internal"."handle_study_created"() TO "service_role";



GRANT ALL ON FUNCTION "internal"."handle_study_deleted"() TO "anon";
GRANT ALL ON FUNCTION "internal"."handle_study_deleted"() TO "authenticated";
GRANT ALL ON FUNCTION "internal"."handle_study_deleted"() TO "service_role";



GRANT ALL ON FUNCTION "internal"."handle_study_environment_deleted"() TO "anon";
GRANT ALL ON FUNCTION "internal"."handle_study_environment_deleted"() TO "authenticated";
GRANT ALL ON FUNCTION "internal"."handle_study_environment_deleted"() TO "service_role";



GRANT ALL ON FUNCTION "internal"."handle_study_environment_file_key_updated"() TO "anon";
GRANT ALL ON FUNCTION "internal"."handle_study_environment_file_key_updated"() TO "authenticated";
GRANT ALL ON FUNCTION "internal"."handle_study_environment_file_key_updated"() TO "service_role";



GRANT ALL ON FUNCTION "internal"."handle_study_file_key_updated"() TO "anon";
GRANT ALL ON FUNCTION "internal"."handle_study_file_key_updated"() TO "authenticated";
GRANT ALL ON FUNCTION "internal"."handle_study_file_key_updated"() TO "service_role";



GRANT ALL ON FUNCTION "internal"."handle_study_participant_deleted"() TO "anon";
GRANT ALL ON FUNCTION "internal"."handle_study_participant_deleted"() TO "authenticated";
GRANT ALL ON FUNCTION "internal"."handle_study_participant_deleted"() TO "service_role";



GRANT ALL ON FUNCTION "internal"."handle_study_participant_file_key_updated"() TO "anon";
GRANT ALL ON FUNCTION "internal"."handle_study_participant_file_key_updated"() TO "authenticated";
GRANT ALL ON FUNCTION "internal"."handle_study_participant_file_key_updated"() TO "service_role";



GRANT ALL ON FUNCTION "internal"."handle_user_created"() TO "anon";
GRANT ALL ON FUNCTION "internal"."handle_user_created"() TO "authenticated";
GRANT ALL ON FUNCTION "internal"."handle_user_created"() TO "service_role";



























GRANT ALL ON TABLE "internal"."active_users" TO "anon";
GRANT ALL ON TABLE "internal"."active_users" TO "authenticated";
GRANT ALL ON TABLE "internal"."active_users" TO "service_role";



GRANT ALL ON TABLE "internal"."additional_user_information" TO "anon";
GRANT ALL ON TABLE "internal"."additional_user_information" TO "authenticated";
GRANT ALL ON TABLE "internal"."additional_user_information" TO "service_role";



GRANT ALL ON TABLE "internal"."application_versions" TO "anon";
GRANT ALL ON TABLE "internal"."application_versions" TO "authenticated";
GRANT ALL ON TABLE "internal"."application_versions" TO "service_role";



GRANT ALL ON SEQUENCE "internal"."application_version_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "internal"."application_version_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "internal"."application_version_id_seq" TO "service_role";



GRANT ALL ON TABLE "internal"."applications" TO "anon";
GRANT ALL ON TABLE "internal"."applications" TO "authenticated";
GRANT ALL ON TABLE "internal"."applications" TO "service_role";



GRANT ALL ON TABLE "internal"."business_units" TO "anon";
GRANT ALL ON TABLE "internal"."business_units" TO "authenticated";
GRANT ALL ON TABLE "internal"."business_units" TO "service_role";



GRANT ALL ON SEQUENCE "internal"."business_units_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "internal"."business_units_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "internal"."business_units_id_seq" TO "service_role";



GRANT ALL ON TABLE "internal"."max_concurrent_connections" TO "anon";
GRANT ALL ON TABLE "internal"."max_concurrent_connections" TO "authenticated";
GRANT ALL ON TABLE "internal"."max_concurrent_connections" TO "service_role";



GRANT ALL ON SEQUENCE "internal"."max_logins_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "internal"."max_logins_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "internal"."max_logins_id_seq" TO "service_role";



GRANT ALL ON TABLE "internal"."product_categories" TO "anon";
GRANT ALL ON TABLE "internal"."product_categories" TO "authenticated";
GRANT ALL ON TABLE "internal"."product_categories" TO "service_role";



GRANT ALL ON TABLE "internal"."product_categories_access" TO "anon";
GRANT ALL ON TABLE "internal"."product_categories_access" TO "authenticated";
GRANT ALL ON TABLE "internal"."product_categories_access" TO "service_role";



GRANT ALL ON SEQUENCE "internal"."product_categories_access_business_unit_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "internal"."product_categories_access_business_unit_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "internal"."product_categories_access_business_unit_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "internal"."product_categories_access_product_category_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "internal"."product_categories_access_product_category_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "internal"."product_categories_access_product_category_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "internal"."product_categories_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "internal"."product_categories_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "internal"."product_categories_id_seq" TO "service_role";



GRANT ALL ON TABLE "internal"."products" TO "anon";
GRANT ALL ON TABLE "internal"."products" TO "authenticated";
GRANT ALL ON TABLE "internal"."products" TO "service_role";



GRANT ALL ON SEQUENCE "internal"."products_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "internal"."products_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "internal"."products_id_seq" TO "service_role";



GRANT ALL ON TABLE "internal"."study_scenarios" TO "anon";
GRANT ALL ON TABLE "internal"."study_scenarios" TO "authenticated";
GRANT ALL ON TABLE "internal"."study_scenarios" TO "service_role";



GRANT ALL ON SEQUENCE "internal"."scenario_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "internal"."scenario_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "internal"."scenario_id_seq" TO "service_role";



GRANT ALL ON TABLE "internal"."sindri_folders" TO "anon";
GRANT ALL ON TABLE "internal"."sindri_folders" TO "authenticated";
GRANT ALL ON TABLE "internal"."sindri_folders" TO "service_role";



GRANT ALL ON SEQUENCE "internal"."sindri_folder_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "internal"."sindri_folder_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "internal"."sindri_folder_id_seq" TO "service_role";



GRANT ALL ON TABLE "internal"."sindri_folders_access" TO "anon";
GRANT ALL ON TABLE "internal"."sindri_folders_access" TO "authenticated";
GRANT ALL ON TABLE "internal"."sindri_folders_access" TO "service_role";



GRANT ALL ON SEQUENCE "internal"."sindri_folders_access_business_unit_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "internal"."sindri_folders_access_business_unit_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "internal"."sindri_folders_access_business_unit_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "internal"."sindri_folders_access_sindri_folder_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "internal"."sindri_folders_access_sindri_folder_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "internal"."sindri_folders_access_sindri_folder_id_seq" TO "service_role";



GRANT ALL ON TABLE "internal"."sindri_saves" TO "anon";
GRANT ALL ON TABLE "internal"."sindri_saves" TO "authenticated";
GRANT ALL ON TABLE "internal"."sindri_saves" TO "service_role";



GRANT ALL ON SEQUENCE "internal"."sindri_save_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "internal"."sindri_save_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "internal"."sindri_save_id_seq" TO "service_role";



GRANT ALL ON TABLE "internal"."studies" TO "anon";
GRANT ALL ON TABLE "internal"."studies" TO "authenticated";
GRANT ALL ON TABLE "internal"."studies" TO "service_role";



GRANT ALL ON TABLE "internal"."studies_access" TO "anon";
GRANT ALL ON TABLE "internal"."studies_access" TO "authenticated";
GRANT ALL ON TABLE "internal"."studies_access" TO "service_role";



GRANT ALL ON SEQUENCE "internal"."studies_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "internal"."studies_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "internal"."studies_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "internal"."study_access_business_unit_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "internal"."study_access_business_unit_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "internal"."study_access_business_unit_id_seq" TO "service_role";



GRANT ALL ON TABLE "internal"."study_computers" TO "anon";
GRANT ALL ON TABLE "internal"."study_computers" TO "authenticated";
GRANT ALL ON TABLE "internal"."study_computers" TO "service_role";



GRANT ALL ON SEQUENCE "internal"."study_computers_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "internal"."study_computers_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "internal"."study_computers_id_seq" TO "service_role";



GRANT ALL ON TABLE "internal"."study_environments" TO "anon";
GRANT ALL ON TABLE "internal"."study_environments" TO "authenticated";
GRANT ALL ON TABLE "internal"."study_environments" TO "service_role";



GRANT ALL ON TABLE "internal"."study_monads" TO "anon";
GRANT ALL ON TABLE "internal"."study_monads" TO "authenticated";
GRANT ALL ON TABLE "internal"."study_monads" TO "service_role";



GRANT ALL ON SEQUENCE "internal"."study_monad_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "internal"."study_monad_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "internal"."study_monad_id_seq" TO "service_role";



GRANT ALL ON TABLE "internal"."study_participants" TO "anon";
GRANT ALL ON TABLE "internal"."study_participants" TO "authenticated";
GRANT ALL ON TABLE "internal"."study_participants" TO "service_role";



GRANT ALL ON SEQUENCE "internal"."study_participants_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "internal"."study_participants_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "internal"."study_participants_id_seq" TO "service_role";



GRANT ALL ON TABLE "internal"."study_tasks" TO "anon";
GRANT ALL ON TABLE "internal"."study_tasks" TO "authenticated";
GRANT ALL ON TABLE "internal"."study_tasks" TO "service_role";



GRANT ALL ON SEQUENCE "internal"."study_tasks_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "internal"."study_tasks_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "internal"."study_tasks_id_seq" TO "service_role";



GRANT ALL ON TABLE "internal"."user_application_permissions" TO "anon";
GRANT ALL ON TABLE "internal"."user_application_permissions" TO "authenticated";
GRANT ALL ON TABLE "internal"."user_application_permissions" TO "service_role";



GRANT ALL ON SEQUENCE "internal"."user_application_permissions_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "internal"."user_application_permissions_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "internal"."user_application_permissions_id_seq" TO "service_role";












ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "internal" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "internal" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "internal" GRANT ALL ON SEQUENCES  TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "internal" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "internal" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "internal" GRANT ALL ON FUNCTIONS  TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "internal" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "internal" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "internal" GRANT ALL ON TABLES  TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";






























RESET ALL;
