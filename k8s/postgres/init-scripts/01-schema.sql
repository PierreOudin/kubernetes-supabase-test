--
-- PostgreSQL database dump
--

-- Dumped from database version 15.1 (Ubuntu 15.1-1.pgdg20.04+1)
-- Dumped by pg_dump version 15.7 (Ubuntu 15.7-1.pgdg20.04+1)

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

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: auth_id(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.auth_id() RETURNS uuid
    LANGUAGE sql SECURITY DEFINER
    AS $$
  (SELECT "idExterne" FROM public."Users" WHERE "idSupabase" = auth.uid());  
$$;


ALTER FUNCTION public.auth_id() OWNER TO supabase_admin;

--
-- Name: channel_already_exist(uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.channel_already_exist(creatorid uuid, userid uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$ 
BEGIN
  RETURN 
    (SELECT c.id from "Channels" c
    inner join public."ChannelUsers" cu on cu."channelId" = c.id 
    inner join public."ChannelUsers" cu2 on cu2."channelId" = c.id
    WHERE cu."authorId" = userid and cu2."authorId" = creatorid and c."isGroupChat" = false
  );
END
$$;


ALTER FUNCTION public.channel_already_exist(creatorid uuid, userid uuid) OWNER TO postgres;

--
-- Name: create_channel(uuid[], uuid, boolean, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_channel(ids uuid[], creatorid uuid, isgroup boolean, name text) RETURNS integer
    LANGUAGE plpgsql
    AS $$DECLARE
    channelid INTEGER;
	userid UUID;
	existingid INTEGER;
BEGIN	
	-- Check if a one to one already exist
	IF array_length(ids, 1) < 2 THEN
		SELECT channel_already_exist(ids[1], creatorid) INTO existingid;
		IF existingid IS NOT NULL THEN
			RETURN existingid;
		END IF;
	END IF;
	
	-- Create channel
    INSERT INTO public."Channels"("creatorId", "isGroupChat", name)
	VALUES (creatorid, isgroup, name)
	RETURNING id INTO channelid;
	
	-- Add every members
	FOREACH userid IN ARRAY ids LOOP
		INSERT INTO public."ChannelUsers"("authorId", "channelId")
		VALUES (userid, channelid);
	END LOOP;
	
	-- Add creator as admin
	INSERT INTO public."ChannelUsers"("authorId", "channelId", "isAdmin")
	VALUES (creatorid, channelid, true);
	
	RETURN channelid;
END;$$;


ALTER FUNCTION public.create_channel(ids uuid[], creatorid uuid, isgroup boolean, name text) OWNER TO postgres;

--
-- Name: existing_channels(uuid[], uuid); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.existing_channels(users uuid[], creatorid uuid) RETURNS TABLE(channelid bigint, userid uuid)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
  WITH "channelIdCTE" AS (
    SELECT cu."channelId" as "channelId", cu."authorId" as "userId"
    FROM public."ChannelUsers" cu JOIN public."Channels" c on c.id = cu."channelId"
    WHERE cu."authorId" = ANY(users) 
    AND c."isGroupChat" = false
  )
  SELECT cu2."channelId", "userId"
      FROM public."ChannelUsers" cu2, "channelIdCTE" cte 
      WHERE cu2."channelId" = cte."channelId" AND cu2."authorId" = creatorid;
END;
$$;


ALTER FUNCTION public.existing_channels(users uuid[], creatorid uuid) OWNER TO supabase_admin;

--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  DECLARE idExterneText TEXT;
  BEGIN
    idExterneText := new.raw_user_meta_data ->> 'idExterne';

    INSERT INTO public."Users" 
      ("idExterne", firstname, lastname, "avatarUrl", "idSupabase")
    VALUES 
      (idExterneText::uuid, 
      new.raw_user_meta_data ->> 'firstname',
      new.raw_user_meta_data ->> 'lastname',
      new.raw_user_meta_data ->> 'avatarUrl',
      new.id)
    ON CONFLICT("idExterne") 
    DO UPDATE SET
    "idSupabase" = new.id;
    
    return new;
END;
$$;


ALTER FUNCTION public.handle_new_user() OWNER TO supabase_admin;

--
-- Name: inser_msg_user_add(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.inser_msg_user_add() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
  IF ((SELECT c."isGroupChat" from "Channels" as c WHERE c.id = new."channelId" LIMIT 1) AND
  (SELECT c."legacyId" from "Channels" as c WHERE c.id = new."channelId" LIMIT 1) IS NULL)
    THEN
    insert into public."Messages" ("channelId", content)
    values (new."channelId", CONCAT('[USER_ADDED]', (SELECT firstname FROM public."Users" where "idExterne" = new."authorId"), ' ',(SELECT lastname FROM public."Users" where "idExterne" = new."authorId")));
  END IF;  
  return new;
END;$$;


ALTER FUNCTION public.inser_msg_user_add() OWNER TO supabase_admin;

--
-- Name: inser_msg_user_delete(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.inser_msg_user_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF(EXISTS(SELECT public."Channels".id FROM public."Channels" WHERE public."Channels".id = old."channelId")) THEN
  insert into public."Messages" ("channelId", content)
  values (old."channelId", CONCAT('[USER_REMOVED]', (SELECT firstname FROM public."Users" where public."Users"."idExterne" = old."authorId"), ' ',(SELECT lastname FROM public."Users" where public."Users"."idExterne" = old."authorId")));
  END IF;
  return old;
END;
$$;


ALTER FUNCTION public.inser_msg_user_delete() OWNER TO supabase_admin;

--
-- Name: insert_msg_channel_img_updt(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.insert_msg_channel_img_updt() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
 
  insert into public."Messages" ("channelId", content)
  values (new.id, CONCAT('[CHANNEL_IMG_EDIT]', (SELECT firstname FROM public."Users" where "idExterne" = auth_id()), ' ',(SELECT lastname FROM public."Users" where "idExterne" = auth_id())));
  return new;
  EXCEPTION WHEN OTHERS THEN
  return new;
END;$$;


ALTER FUNCTION public.insert_msg_channel_img_updt() OWNER TO supabase_admin;

--
-- Name: insert_msg_channel_name_updt(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.insert_msg_channel_name_updt() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
 
  insert into public."Messages" ("channelId", content)
  values (new.id, CONCAT('[CHANNEL_RENAMED]', (SELECT firstname FROM public."Users" where "idExterne" = auth_id()), ' ',(SELECT lastname FROM public."Users" where "idExterne" = auth_id())));
  return new;
END;
$$;


ALTER FUNCTION public.insert_msg_channel_name_updt() OWNER TO supabase_admin;

--
-- Name: is_same_channel(uuid, bigint); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.is_same_channel(userid uuid, channelid bigint) RETURNS boolean
    LANGUAGE sql SECURITY DEFINER
    AS $$
SELECT EXISTS (
  SELECT cu."authorId", cu."channelId"
  FROM public."ChannelUsers" AS cu
  WHERE cu."channelId" = channelid
  AND cu."authorId" = userid
);
$$;


ALTER FUNCTION public.is_same_channel(userid uuid, channelid bigint) OWNER TO supabase_admin;

--
-- Name: update_channel_on_message_insert(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_channel_on_message_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE public."Channels"
  SET "lastMessageId" = NEW.id
  WHERE id = NEW."channelId";
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_channel_on_message_insert() OWNER TO supabase_admin;

--
-- Name: update_updated_at_messages(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_updated_at_messages() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW."updatedAt" = now();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_updated_at_messages() OWNER TO supabase_admin;

--
-- Name: update_updated_on_channels(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_updated_on_channels() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW."updatedAt" = now();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_updated_on_channels() OWNER TO supabase_admin;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ChannelUsers; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public."ChannelUsers" (
    id bigint NOT NULL,
    "authorId" uuid NOT NULL,
    "channelId" bigint NOT NULL,
    "isAdmin" boolean DEFAULT false NOT NULL,
    "hasPinned" boolean DEFAULT false NOT NULL,
    "isSilent" boolean DEFAULT false NOT NULL,
    "isHidden" boolean DEFAULT false NOT NULL,
    "dateLastLecture" timestamp with time zone,
    "dateLastReceived" timestamp with time zone,
    "dateMaxHistory" timestamp with time zone,
    "addedAt" timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public."ChannelUsers" OWNER TO supabase_admin;

--
-- Name: ChannelUsers_id_seq; Type: SEQUENCE; Schema: public; Owner: supabase_admin
--

ALTER TABLE public."ChannelUsers" ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."ChannelUsers_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: Channels; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public."Channels" (
    id bigint NOT NULL,
    "lastMessageId" bigint,
    name text,
    "imageUrl" text,
    "creatorId" uuid,
    "isReadOnly" boolean DEFAULT false NOT NULL,
    "isGroupChat" boolean DEFAULT false NOT NULL,
    "updatedAt" timestamp with time zone DEFAULT now() NOT NULL,
    "createdAt" timestamp with time zone DEFAULT now() NOT NULL,
    "legacyId" bigint,
    "idSite" bigint
);


ALTER TABLE public."Channels" OWNER TO supabase_admin;

--
-- Name: Channels_id_seq; Type: SEQUENCE; Schema: public; Owner: supabase_admin
--

ALTER TABLE public."Channels" ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."Channels_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: FcmTokens; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public."FcmTokens" (
    token text NOT NULL,
    "userId" uuid NOT NULL,
    "isLoggedIn" boolean DEFAULT false NOT NULL,
    "deviceId" uuid NOT NULL
);


ALTER TABLE public."FcmTokens" OWNER TO supabase_admin;

--
-- Name: Messages; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public."Messages" (
    id bigint NOT NULL,
    "channelId" bigint NOT NULL,
    "authorId" uuid,
    content text NOT NULL,
    "rawContent" text,
    "replyId" bigint,
    "isImportant" boolean DEFAULT false NOT NULL,
    "isDeleted" boolean DEFAULT false NOT NULL,
    "updatedAt" timestamp with time zone,
    "createdAt" timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public."Messages" OWNER TO supabase_admin;

--
-- Name: Messages_id_seq; Type: SEQUENCE; Schema: public; Owner: supabase_admin
--

ALTER TABLE public."Messages" ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."Messages_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: Migrations; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public."Migrations" (
    id bigint NOT NULL,
    "siteId" bigint NOT NULL,
    "startedAt" timestamp with time zone DEFAULT now() NOT NULL,
    "endedAt" timestamp with time zone,
    status boolean
);


ALTER TABLE public."Migrations" OWNER TO supabase_admin;

--
-- Name: Migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: supabase_admin
--

ALTER TABLE public."Migrations" ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public."Migrations_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: Users; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public."Users" (
    "idExterne" uuid NOT NULL,
    "idSupabase" uuid,
    firstname text NOT NULL,
    lastname text,
    "avatarUrl" text,
    "createdAt" timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    "isService" boolean
);


ALTER TABLE public."Users" OWNER TO supabase_admin;

--
-- Name: ChannelUsers ChannelUsers_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public."ChannelUsers"
    ADD CONSTRAINT "ChannelUsers_pkey" PRIMARY KEY (id);


--
-- Name: Channels Channels_id_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public."Channels"
    ADD CONSTRAINT "Channels_id_key" UNIQUE (id);


--
-- Name: Channels Channels_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public."Channels"
    ADD CONSTRAINT "Channels_pkey" PRIMARY KEY (id);


--
-- Name: FcmTokens FcmTokens_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public."FcmTokens"
    ADD CONSTRAINT "FcmTokens_pkey" PRIMARY KEY (token);


--
-- Name: Messages Messages_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public."Messages"
    ADD CONSTRAINT "Messages_pkey" PRIMARY KEY (id);


--
-- Name: Migrations Migrations_id_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public."Migrations"
    ADD CONSTRAINT "Migrations_id_key" UNIQUE (id);


--
-- Name: Migrations Migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public."Migrations"
    ADD CONSTRAINT "Migrations_pkey" PRIMARY KEY (id);


--
-- Name: Users Users_idExterne_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public."Users"
    ADD CONSTRAINT "Users_idExterne_key" UNIQUE ("idSupabase");


--
-- Name: ChannelUsers unique_channel_user; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public."ChannelUsers"
    ADD CONSTRAINT unique_channel_user UNIQUE ("channelId", "authorId");


--
-- Name: Users users_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public."Users"
    ADD CONSTRAINT users_pkey PRIMARY KEY ("idExterne");


--
-- Name: Channels channelimageupdated; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER channelimageupdated AFTER UPDATE OF "imageUrl" ON public."Channels" FOR EACH ROW EXECUTE FUNCTION public.insert_msg_channel_img_updt();


--
-- Name: Channels channelnameupdated; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER channelnameupdated AFTER UPDATE OF name ON public."Channels" FOR EACH ROW EXECUTE FUNCTION public.insert_msg_channel_name_updt();


--
-- Name: Messages notif new message; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER "notif new message" AFTER INSERT ON public."Messages" FOR EACH ROW EXECUTE FUNCTION supabase_functions.http_request('http://localhost:8000/functions/v1/notif', 'POST', '{"Content-type":"application/json"}', '{}', '1000');


--
-- Name: Messages update_channel_on_message_insert; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER update_channel_on_message_insert AFTER INSERT ON public."Messages" FOR EACH ROW EXECUTE FUNCTION public.update_channel_on_message_insert();


--
-- Name: Channels update_channel_updated_on; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER update_channel_updated_on BEFORE UPDATE ON public."Channels" FOR EACH ROW EXECUTE FUNCTION public.update_updated_on_channels();


--
-- Name: Messages update_message_updated_at; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER update_message_updated_at BEFORE UPDATE ON public."Messages" FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_messages();


--
-- Name: ChannelUsers userdeleted; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER userdeleted BEFORE DELETE ON public."ChannelUsers" FOR EACH ROW EXECUTE FUNCTION public.inser_msg_user_delete();


--
-- Name: ChannelUsers userinserted; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER userinserted AFTER INSERT ON public."ChannelUsers" FOR EACH ROW EXECUTE FUNCTION public.inser_msg_user_add();


--
-- Name: ChannelUsers public_ChannelUsers_authorId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public."ChannelUsers"
    ADD CONSTRAINT "public_ChannelUsers_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES public."Users"("idExterne") ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: ChannelUsers public_ChannelUsers_channelId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public."ChannelUsers"
    ADD CONSTRAINT "public_ChannelUsers_channelId_fkey" FOREIGN KEY ("channelId") REFERENCES public."Channels"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: Channels public_Channels_creatorId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public."Channels"
    ADD CONSTRAINT "public_Channels_creatorId_fkey" FOREIGN KEY ("creatorId") REFERENCES public."Users"("idExterne") ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: FcmTokens public_FcmTokens_userId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public."FcmTokens"
    ADD CONSTRAINT "public_FcmTokens_userId_fkey" FOREIGN KEY ("userId") REFERENCES public."Users"("idExterne") ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: Messages public_Messages_authorId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public."Messages"
    ADD CONSTRAINT "public_Messages_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES public."Users"("idExterne") ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: Messages public_Messages_channelId_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public."Messages"
    ADD CONSTRAINT "public_Messages_channelId_fkey" FOREIGN KEY ("channelId") REFERENCES public."Channels"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: Users public_Users_idExterne_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public."Users"
    ADD CONSTRAINT "public_Users_idExterne_fkey" FOREIGN KEY ("idSupabase") REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: Channels Channel DELETE based on user Id or count; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Channel DELETE based on user Id or count" ON public."Channels" FOR DELETE USING ((public.is_same_channel(public.auth_id(), id) OR (( SELECT count("ChannelUsers"."channelId") AS count
   FROM public."ChannelUsers"
  WHERE ("ChannelUsers"."channelId" = "ChannelUsers".id)) = 1)));


--
-- Name: Channels Channel INSERT based on authenticated; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Channel INSERT based on authenticated" ON public."Channels" FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: Channels Channel SELECT based on user Id; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Channel SELECT based on user Id" ON public."Channels" FOR SELECT USING (((EXISTS ( SELECT cu.id,
    cu."authorId",
    cu."channelId"
   FROM public."ChannelUsers" cu
  WHERE (("Channels".id = cu."channelId") AND (cu."authorId" = public.auth_id())))) OR (public.auth_id() = "creatorId")));


--
-- Name: Channels Channel UPDATE based on user Id; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Channel UPDATE based on user Id" ON public."Channels" FOR UPDATE USING (((EXISTS ( SELECT cu."authorId",
    cu."channelId"
   FROM public."ChannelUsers" cu
  WHERE (("Channels".id = cu."channelId") AND (public.auth_id() = cu."authorId")))) OR ("creatorId" = public.auth_id())));


--
-- Name: ChannelUsers ChannelUser UPDATE based on userId; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "ChannelUser UPDATE based on userId" ON public."ChannelUsers" FOR UPDATE USING ((public.auth_id() = "authorId"));


--
-- Name: ChannelUsers ChannelUsers DELETE based on user Id; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "ChannelUsers DELETE based on user Id" ON public."ChannelUsers" FOR DELETE USING ((public.is_same_channel(public.auth_id(), "channelId") AND (( SELECT cu."isAdmin"
   FROM public."ChannelUsers" cu
  WHERE ((cu."channelId" = "ChannelUsers"."channelId") AND (cu."authorId" = public.auth_id()))) OR (public.auth_id() = "authorId"))));


--
-- Name: ChannelUsers ChannelUsers INSERT based on authenticated; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "ChannelUsers INSERT based on authenticated" ON public."ChannelUsers" FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: ChannelUsers ChannelUsers SELECT based on user Id; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "ChannelUsers SELECT based on user Id" ON public."ChannelUsers" FOR SELECT USING (public.is_same_channel(public.auth_id(), "channelId"));


--
-- Name: FcmTokens Enable all for authenticated users only; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Enable all for authenticated users only" ON public."FcmTokens" TO authenticated USING (true) WITH CHECK (true);


--
-- Name: Users Enable insert for authenticated users only; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Enable insert for authenticated users only" ON public."Users" FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: FcmTokens; Type: ROW SECURITY; Schema: public; Owner: supabase_admin
--

ALTER TABLE public."FcmTokens" ENABLE ROW LEVEL SECURITY;

--
-- Name: Messages Messages INSERT based on user Id; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Messages INSERT based on user Id" ON public."Messages" FOR INSERT WITH CHECK ((EXISTS ( SELECT c.id,
    c."lastMessageId",
    c.name,
    c."isReadOnly",
    c."createdAt",
    c."updatedAt"
   FROM public."Channels" c
  WHERE (("Messages"."channelId" = c.id) AND (EXISTS ( SELECT cu.id,
            cu."authorId",
            cu."channelId",
            cu."dateLastLecture",
            cu."isAdmin",
            cu."hasPinned",
            cu."addedAt"
           FROM public."ChannelUsers" cu
          WHERE ((c.id = cu."channelId") AND (cu."authorId" = public.auth_id()))))))));


--
-- Name: Messages Messages SELECT based on user Id; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Messages SELECT based on user Id" ON public."Messages" FOR SELECT USING ((EXISTS ( SELECT c.id
   FROM public."Channels" c
  WHERE (("Messages"."channelId" = c.id) AND (EXISTS ( SELECT cu.id,
            cu."authorId",
            cu."channelId",
            cu."dateMaxHistory"
           FROM public."ChannelUsers" cu
          WHERE ((c.id = cu."channelId") AND (cu."authorId" = public.auth_id()))))))));


--
-- Name: Messages Messages UPDATE based on user Id; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Messages UPDATE based on user Id" ON public."Messages" FOR UPDATE USING ((public.auth_id() = "authorId"));


--
-- Name: Migrations; Type: ROW SECURITY; Schema: public; Owner: supabase_admin
--

ALTER TABLE public."Migrations" ENABLE ROW LEVEL SECURITY;

--
-- Name: Users SELECT User if authenticated; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "SELECT User if authenticated" ON public."Users" FOR SELECT TO authenticated USING (true);


--
-- Name: Users UPDATE own User only; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "UPDATE own User only" ON public."Users" FOR UPDATE USING ((public.auth_id() = "idExterne"));


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION auth_id(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.auth_id() TO postgres;
GRANT ALL ON FUNCTION public.auth_id() TO anon;
GRANT ALL ON FUNCTION public.auth_id() TO authenticated;
GRANT ALL ON FUNCTION public.auth_id() TO service_role;


--
-- Name: FUNCTION channel_already_exist(creatorid uuid, userid uuid); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.channel_already_exist(creatorid uuid, userid uuid) TO anon;
GRANT ALL ON FUNCTION public.channel_already_exist(creatorid uuid, userid uuid) TO authenticated;
GRANT ALL ON FUNCTION public.channel_already_exist(creatorid uuid, userid uuid) TO service_role;


--
-- Name: FUNCTION create_channel(ids uuid[], creatorid uuid, isgroup boolean, name text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.create_channel(ids uuid[], creatorid uuid, isgroup boolean, name text) TO anon;
GRANT ALL ON FUNCTION public.create_channel(ids uuid[], creatorid uuid, isgroup boolean, name text) TO authenticated;
GRANT ALL ON FUNCTION public.create_channel(ids uuid[], creatorid uuid, isgroup boolean, name text) TO service_role;


--
-- Name: FUNCTION existing_channels(users uuid[], creatorid uuid); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.existing_channels(users uuid[], creatorid uuid) TO postgres;
GRANT ALL ON FUNCTION public.existing_channels(users uuid[], creatorid uuid) TO anon;
GRANT ALL ON FUNCTION public.existing_channels(users uuid[], creatorid uuid) TO authenticated;
GRANT ALL ON FUNCTION public.existing_channels(users uuid[], creatorid uuid) TO service_role;


--
-- Name: FUNCTION handle_new_user(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.handle_new_user() TO postgres;
GRANT ALL ON FUNCTION public.handle_new_user() TO anon;
GRANT ALL ON FUNCTION public.handle_new_user() TO authenticated;
GRANT ALL ON FUNCTION public.handle_new_user() TO service_role;


--
-- Name: FUNCTION inser_msg_user_add(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.inser_msg_user_add() TO postgres;
GRANT ALL ON FUNCTION public.inser_msg_user_add() TO anon;
GRANT ALL ON FUNCTION public.inser_msg_user_add() TO authenticated;
GRANT ALL ON FUNCTION public.inser_msg_user_add() TO service_role;


--
-- Name: FUNCTION inser_msg_user_delete(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.inser_msg_user_delete() TO postgres;
GRANT ALL ON FUNCTION public.inser_msg_user_delete() TO anon;
GRANT ALL ON FUNCTION public.inser_msg_user_delete() TO authenticated;
GRANT ALL ON FUNCTION public.inser_msg_user_delete() TO service_role;


--
-- Name: FUNCTION insert_msg_channel_img_updt(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.insert_msg_channel_img_updt() TO postgres;
GRANT ALL ON FUNCTION public.insert_msg_channel_img_updt() TO anon;
GRANT ALL ON FUNCTION public.insert_msg_channel_img_updt() TO authenticated;
GRANT ALL ON FUNCTION public.insert_msg_channel_img_updt() TO service_role;


--
-- Name: FUNCTION insert_msg_channel_name_updt(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.insert_msg_channel_name_updt() TO postgres;
GRANT ALL ON FUNCTION public.insert_msg_channel_name_updt() TO anon;
GRANT ALL ON FUNCTION public.insert_msg_channel_name_updt() TO authenticated;
GRANT ALL ON FUNCTION public.insert_msg_channel_name_updt() TO service_role;


--
-- Name: FUNCTION is_same_channel(userid uuid, channelid bigint); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.is_same_channel(userid uuid, channelid bigint) TO postgres;
GRANT ALL ON FUNCTION public.is_same_channel(userid uuid, channelid bigint) TO anon;
GRANT ALL ON FUNCTION public.is_same_channel(userid uuid, channelid bigint) TO authenticated;
GRANT ALL ON FUNCTION public.is_same_channel(userid uuid, channelid bigint) TO service_role;


--
-- Name: FUNCTION update_channel_on_message_insert(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_channel_on_message_insert() TO postgres;
GRANT ALL ON FUNCTION public.update_channel_on_message_insert() TO anon;
GRANT ALL ON FUNCTION public.update_channel_on_message_insert() TO authenticated;
GRANT ALL ON FUNCTION public.update_channel_on_message_insert() TO service_role;


--
-- Name: FUNCTION update_updated_at_messages(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_updated_at_messages() TO postgres;
GRANT ALL ON FUNCTION public.update_updated_at_messages() TO anon;
GRANT ALL ON FUNCTION public.update_updated_at_messages() TO authenticated;
GRANT ALL ON FUNCTION public.update_updated_at_messages() TO service_role;


--
-- Name: FUNCTION update_updated_on_channels(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_updated_on_channels() TO postgres;
GRANT ALL ON FUNCTION public.update_updated_on_channels() TO anon;
GRANT ALL ON FUNCTION public.update_updated_on_channels() TO authenticated;
GRANT ALL ON FUNCTION public.update_updated_on_channels() TO service_role;


--
-- Name: TABLE "ChannelUsers"; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public."ChannelUsers" TO postgres;
GRANT ALL ON TABLE public."ChannelUsers" TO anon;
GRANT ALL ON TABLE public."ChannelUsers" TO authenticated;
GRANT ALL ON TABLE public."ChannelUsers" TO service_role;


--
-- Name: SEQUENCE "ChannelUsers_id_seq"; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON SEQUENCE public."ChannelUsers_id_seq" TO postgres;
GRANT ALL ON SEQUENCE public."ChannelUsers_id_seq" TO anon;
GRANT ALL ON SEQUENCE public."ChannelUsers_id_seq" TO authenticated;
GRANT ALL ON SEQUENCE public."ChannelUsers_id_seq" TO service_role;


--
-- Name: TABLE "Channels"; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public."Channels" TO postgres;
GRANT ALL ON TABLE public."Channels" TO anon;
GRANT ALL ON TABLE public."Channels" TO authenticated;
GRANT ALL ON TABLE public."Channels" TO service_role;


--
-- Name: SEQUENCE "Channels_id_seq"; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON SEQUENCE public."Channels_id_seq" TO postgres;
GRANT ALL ON SEQUENCE public."Channels_id_seq" TO anon;
GRANT ALL ON SEQUENCE public."Channels_id_seq" TO authenticated;
GRANT ALL ON SEQUENCE public."Channels_id_seq" TO service_role;


--
-- Name: TABLE "FcmTokens"; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public."FcmTokens" TO postgres;
GRANT ALL ON TABLE public."FcmTokens" TO anon;
GRANT ALL ON TABLE public."FcmTokens" TO authenticated;
GRANT ALL ON TABLE public."FcmTokens" TO service_role;


--
-- Name: TABLE "Messages"; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public."Messages" TO postgres;
GRANT ALL ON TABLE public."Messages" TO anon;
GRANT ALL ON TABLE public."Messages" TO authenticated;
GRANT ALL ON TABLE public."Messages" TO service_role;


--
-- Name: SEQUENCE "Messages_id_seq"; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON SEQUENCE public."Messages_id_seq" TO postgres;
GRANT ALL ON SEQUENCE public."Messages_id_seq" TO anon;
GRANT ALL ON SEQUENCE public."Messages_id_seq" TO authenticated;
GRANT ALL ON SEQUENCE public."Messages_id_seq" TO service_role;


--
-- Name: TABLE "Migrations"; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public."Migrations" TO postgres;
GRANT ALL ON TABLE public."Migrations" TO anon;
GRANT ALL ON TABLE public."Migrations" TO authenticated;
GRANT ALL ON TABLE public."Migrations" TO service_role;


--
-- Name: SEQUENCE "Migrations_id_seq"; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON SEQUENCE public."Migrations_id_seq" TO postgres;
GRANT ALL ON SEQUENCE public."Migrations_id_seq" TO anon;
GRANT ALL ON SEQUENCE public."Migrations_id_seq" TO authenticated;
GRANT ALL ON SEQUENCE public."Migrations_id_seq" TO service_role;


--
-- Name: TABLE "Users"; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public."Users" TO postgres;
GRANT ALL ON TABLE public."Users" TO anon;
GRANT ALL ON TABLE public."Users" TO authenticated;
GRANT ALL ON TABLE public."Users" TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES  TO service_role;


--
-- PostgreSQL database dump complete
--

