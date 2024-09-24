grant delete on table "storage"."s3_multipart_uploads" to "postgres";

grant insert on table "storage"."s3_multipart_uploads" to "postgres";

grant references on table "storage"."s3_multipart_uploads" to "postgres";

grant select on table "storage"."s3_multipart_uploads" to "postgres";

grant trigger on table "storage"."s3_multipart_uploads" to "postgres";

grant truncate on table "storage"."s3_multipart_uploads" to "postgres";

grant update on table "storage"."s3_multipart_uploads" to "postgres";

grant delete on table "storage"."s3_multipart_uploads_parts" to "postgres";

grant insert on table "storage"."s3_multipart_uploads_parts" to "postgres";

grant references on table "storage"."s3_multipart_uploads_parts" to "postgres";

grant select on table "storage"."s3_multipart_uploads_parts" to "postgres";

grant trigger on table "storage"."s3_multipart_uploads_parts" to "postgres";

grant truncate on table "storage"."s3_multipart_uploads_parts" to "postgres";

grant update on table "storage"."s3_multipart_uploads_parts" to "postgres";

create policy "environment_images_delete"
on "storage"."objects"
as permissive
for delete
to authenticated
using (((bucket_id = 'environment_images'::text) AND (auth.role() = 'authenticated'::text) AND ( SELECT internal.get_is_admin() AS get_is_admin)));


create policy "environment_images_insert"
on "storage"."objects"
as permissive
for insert
to authenticated
with check (((bucket_id = 'environment_images'::text) AND (auth.role() = 'authenticated'::text) AND ( SELECT internal.get_is_admin() AS get_is_admin)));


create policy "environment_images_select"
on "storage"."objects"
as permissive
for select
to authenticated
using (((bucket_id = 'environment_images'::text) AND (auth.role() = 'authenticated'::text)));


create policy "environment_images_update"
on "storage"."objects"
as permissive
for update
to authenticated
using (((bucket_id = 'environment_images'::text) AND (auth.role() = 'authenticated'::text) AND ( SELECT internal.get_is_admin() AS get_is_admin)));


create policy "participant_files_delete"
on "storage"."objects"
as permissive
for delete
to authenticated
using (((bucket_id = 'participant_files'::text) AND (auth.role() = 'authenticated'::text) AND ((( SELECT split_part(objects.name, '_'::text, 1) AS split_part))::bigint IN ( SELECT internal.get_accessible_study_ids(true) AS get_accessible_study_ids))));


create policy "participant_files_insert"
on "storage"."objects"
as permissive
for insert
to authenticated
with check (((bucket_id = 'participant_files'::text) AND (auth.role() = 'authenticated'::text) AND ((( SELECT split_part(objects.name, '_'::text, 1) AS split_part))::bigint IN ( SELECT internal.get_accessible_study_ids(true) AS get_accessible_study_ids))));


create policy "participant_files_select"
on "storage"."objects"
as permissive
for select
to authenticated
using (((bucket_id = 'participant_files'::text) AND (auth.role() = 'authenticated'::text) AND ((( SELECT split_part(objects.name, '_'::text, 1) AS split_part))::bigint IN ( SELECT internal.get_accessible_study_ids(false) AS get_accessible_study_ids))));


create policy "participant_files_update"
on "storage"."objects"
as permissive
for update
to authenticated
using (((bucket_id = 'participant_files'::text) AND (auth.role() = 'authenticated'::text) AND ((( SELECT split_part(objects.name, '_'::text, 1) AS split_part))::bigint IN ( SELECT internal.get_accessible_study_ids(true) AS get_accessible_study_ids))));


create policy "product_images_delete"
on "storage"."objects"
as permissive
for delete
to authenticated
using (((bucket_id = 'product_images'::text) AND (auth.role() = 'authenticated'::text) AND (( SELECT products.category_id
   FROM internal.products
  WHERE (products.id = (( SELECT split_part(objects.name, '_'::text, 1) AS split_part))::bigint)
 LIMIT 1) IN ( SELECT internal.get_accessible_product_category_ids(true) AS get_accessible_product_category_ids))));


create policy "product_images_insert"
on "storage"."objects"
as permissive
for insert
to authenticated
with check (((bucket_id = 'product_images'::text) AND (auth.role() = 'authenticated'::text) AND (( SELECT products.category_id
   FROM internal.products
  WHERE (products.id = (( SELECT split_part(objects.name, '_'::text, 1) AS split_part))::bigint)
 LIMIT 1) IN ( SELECT internal.get_accessible_product_category_ids(true) AS get_accessible_product_category_ids))));


create policy "product_images_select"
on "storage"."objects"
as permissive
for select
to authenticated
using (((bucket_id = 'product_images'::text) AND (auth.role() = 'authenticated'::text) AND (( SELECT products.category_id
   FROM internal.products
  WHERE (products.id = (( SELECT split_part(objects.name, '_'::text, 1) AS split_part))::bigint)
 LIMIT 1) IN ( SELECT internal.get_accessible_product_category_ids(false) AS get_accessible_product_category_ids))));


create policy "product_images_update"
on "storage"."objects"
as permissive
for update
to authenticated
using (((bucket_id = 'product_images'::text) AND (auth.role() = 'authenticated'::text) AND (( SELECT products.category_id
   FROM internal.products
  WHERE (products.id = (( SELECT split_part(objects.name, '_'::text, 1) AS split_part))::bigint)
 LIMIT 1) IN ( SELECT internal.get_accessible_product_category_ids(true) AS get_accessible_product_category_ids))));


create policy "study_infos_delete"
on "storage"."objects"
as permissive
for delete
to authenticated
using (((bucket_id = 'study_infos'::text) AND (auth.role() = 'authenticated'::text) AND (( SELECT studies.id
   FROM internal.studies
  WHERE (studies.id = (( SELECT split_part(objects.name, '_'::text, 1) AS split_part))::bigint)
 LIMIT 1) IN ( SELECT internal.get_accessible_study_ids(true) AS get_accessible_study_ids))));


create policy "study_infos_insert"
on "storage"."objects"
as permissive
for insert
to authenticated
with check (((bucket_id = 'study_infos'::text) AND (auth.role() = 'authenticated'::text) AND (( SELECT studies.id
   FROM internal.studies
  WHERE (studies.id = (( SELECT split_part(objects.name, '_'::text, 1) AS split_part))::bigint)
 LIMIT 1) IN ( SELECT internal.get_accessible_study_ids(true) AS get_accessible_study_ids))));


create policy "study_infos_select"
on "storage"."objects"
as permissive
for select
to authenticated
using (((bucket_id = 'study_infos'::text) AND (auth.role() = 'authenticated'::text) AND (( SELECT studies.id
   FROM internal.studies
  WHERE (studies.id = (( SELECT split_part(objects.name, '_'::text, 1) AS split_part))::bigint)
 LIMIT 1) IN ( SELECT internal.get_accessible_study_ids(false) AS get_accessible_study_ids))));


create policy "study_infos_update"
on "storage"."objects"
as permissive
for update
to authenticated
using (((bucket_id = 'study_infos'::text) AND (auth.role() = 'authenticated'::text) AND (( SELECT studies.id
   FROM internal.studies
  WHERE (studies.id = (( SELECT split_part(objects.name, '_'::text, 1) AS split_part))::bigint)
 LIMIT 1) IN ( SELECT internal.get_accessible_study_ids(true) AS get_accessible_study_ids))));


create policy "version_files_delete"
on "storage"."objects"
as permissive
for delete
to authenticated
using (((bucket_id = 'version_files'::text) AND (auth.role() = 'authenticated'::text) AND ( SELECT internal.get_is_admin() AS get_is_admin)));


create policy "version_files_insert"
on "storage"."objects"
as permissive
for insert
to authenticated
with check (((bucket_id = 'version_files'::text) AND (auth.role() = 'authenticated'::text) AND ( SELECT internal.get_is_admin() AS get_is_admin)));


create policy "version_files_select"
on "storage"."objects"
as permissive
for select
to authenticated
using (((bucket_id = 'version_files'::text) AND (auth.role() = 'authenticated'::text)));


create policy "version_files_update"
on "storage"."objects"
as permissive
for update
to authenticated
using (((bucket_id = 'version_files'::text) AND (auth.role() = 'authenticated'::text) AND ( SELECT internal.get_is_admin() AS get_is_admin)));


CREATE TRIGGER on_storage_object_deleted AFTER DELETE ON storage.objects FOR EACH ROW EXECUTE FUNCTION internal.handle_storage_object_deleted();


