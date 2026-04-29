--
-- PostgreSQL database dump
--

\restrict CULHl1YdyPgubfzcgl6xr7bKlcxUaw5R7tuNlb8UCJ1zqEHZnCYG5FFINdwAsW6

-- Dumped from database version 16.13
-- Dumped by pg_dump version 16.13

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

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: activity_logs; Type: TABLE; Schema: public; Owner: fyp_user
--

CREATE TABLE public.activity_logs (
    id integer NOT NULL,
    event_type character varying(100) NOT NULL,
    source character varying(100) DEFAULT 'backend'::character varying,
    severity character varying(20) DEFAULT 'info'::character varying,
    message text NOT NULL,
    pipeline_instance_id integer,
    session_id integer,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.activity_logs OWNER TO fyp_user;

--
-- Name: activity_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: fyp_user
--

CREATE SEQUENCE public.activity_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.activity_logs_id_seq OWNER TO fyp_user;

--
-- Name: activity_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fyp_user
--

ALTER SEQUENCE public.activity_logs_id_seq OWNED BY public.activity_logs.id;


--
-- Name: alert_rules; Type: TABLE; Schema: public; Owner: fyp_user
--

CREATE TABLE public.alert_rules (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    pipeline_instance_id integer,
    model_name character varying(100) NOT NULL,
    trigger_condition jsonb NOT NULL,
    actions jsonb NOT NULL,
    is_active boolean DEFAULT true,
    cooldown_seconds integer DEFAULT 60,
    trigger_count integer DEFAULT 0,
    last_triggered_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.alert_rules OWNER TO fyp_user;

--
-- Name: alert_rules_id_seq; Type: SEQUENCE; Schema: public; Owner: fyp_user
--

CREATE SEQUENCE public.alert_rules_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.alert_rules_id_seq OWNER TO fyp_user;

--
-- Name: alert_rules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fyp_user
--

ALTER SEQUENCE public.alert_rules_id_seq OWNED BY public.alert_rules.id;


--
-- Name: camera_configs; Type: TABLE; Schema: public; Owner: fyp_user
--

CREATE TABLE public.camera_configs (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    source_type character varying(50) NOT NULL,
    source_url character varying(500) NOT NULL,
    fps integer DEFAULT 30,
    width integer DEFAULT 640,
    height integer DEFAULT 480,
    is_default boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    group_name character varying(255),
    enabled_models jsonb DEFAULT '[]'::jsonb,
    model_configs jsonb DEFAULT '{}'::jsonb
);


ALTER TABLE public.camera_configs OWNER TO fyp_user;

--
-- Name: camera_configs_id_seq; Type: SEQUENCE; Schema: public; Owner: fyp_user
--

CREATE SEQUENCE public.camera_configs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.camera_configs_id_seq OWNER TO fyp_user;

--
-- Name: camera_configs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fyp_user
--

ALTER SEQUENCE public.camera_configs_id_seq OWNED BY public.camera_configs.id;


--
-- Name: detection_results; Type: TABLE; Schema: public; Owner: fyp_user
--

CREATE TABLE public.detection_results (
    id integer NOT NULL,
    session_id integer NOT NULL,
    frame_id integer NOT NULL,
    "timestamp" timestamp with time zone DEFAULT now(),
    model_name character varying(100) NOT NULL,
    result_data jsonb NOT NULL,
    confidence double precision,
    processing_time_ms double precision
);


ALTER TABLE public.detection_results OWNER TO fyp_user;

--
-- Name: detection_results_id_seq; Type: SEQUENCE; Schema: public; Owner: fyp_user
--

CREATE SEQUENCE public.detection_results_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.detection_results_id_seq OWNER TO fyp_user;

--
-- Name: detection_results_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fyp_user
--

ALTER SEQUENCE public.detection_results_id_seq OWNED BY public.detection_results.id;


--
-- Name: device_tokens; Type: TABLE; Schema: public; Owner: fyp_user
--

CREATE TABLE public.device_tokens (
    id integer NOT NULL,
    user_id character varying(255),
    device_token character varying(500) NOT NULL,
    platform character varying(50) NOT NULL,
    device_name character varying(255),
    is_active boolean DEFAULT true,
    last_used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.device_tokens OWNER TO fyp_user;

--
-- Name: device_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: fyp_user
--

CREATE SEQUENCE public.device_tokens_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.device_tokens_id_seq OWNER TO fyp_user;

--
-- Name: device_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fyp_user
--

ALTER SEQUENCE public.device_tokens_id_seq OWNED BY public.device_tokens.id;


--
-- Name: pipeline_instances; Type: TABLE; Schema: public; Owner: fyp_user
--

CREATE TABLE public.pipeline_instances (
    id integer NOT NULL,
    session_id integer,
    camera_config_id integer,
    name character varying(255) NOT NULL,
    status character varying(50) DEFAULT 'idle'::character varying,
    enabled_models jsonb DEFAULT '[]'::jsonb,
    model_configs jsonb DEFAULT '{}'::jsonb,
    fps double precision DEFAULT 0,
    frames_processed integer DEFAULT 0,
    last_error text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.pipeline_instances OWNER TO fyp_user;

--
-- Name: pipeline_instances_id_seq; Type: SEQUENCE; Schema: public; Owner: fyp_user
--

CREATE SEQUENCE public.pipeline_instances_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.pipeline_instances_id_seq OWNER TO fyp_user;

--
-- Name: pipeline_instances_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fyp_user
--

ALTER SEQUENCE public.pipeline_instances_id_seq OWNED BY public.pipeline_instances.id;


--
-- Name: recordings; Type: TABLE; Schema: public; Owner: fyp_user
--

CREATE TABLE public.recordings (
    id integer NOT NULL,
    session_id integer,
    pipeline_instance_id integer,
    name character varying(255),
    file_path character varying(500) NOT NULL,
    results_file_path character varying(500),
    file_size_bytes bigint,
    duration_seconds double precision,
    fps double precision,
    width integer,
    height integer,
    codec character varying(50),
    frame_count integer,
    status character varying(50) DEFAULT 'recording'::character varying,
    started_at timestamp with time zone DEFAULT now(),
    ended_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.recordings OWNER TO fyp_user;

--
-- Name: recordings_id_seq; Type: SEQUENCE; Schema: public; Owner: fyp_user
--

CREATE SEQUENCE public.recordings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.recordings_id_seq OWNER TO fyp_user;

--
-- Name: recordings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fyp_user
--

ALTER SEQUENCE public.recordings_id_seq OWNED BY public.recordings.id;


--
-- Name: roi_zones; Type: TABLE; Schema: public; Owner: fyp_user
--

CREATE TABLE public.roi_zones (
    id integer NOT NULL,
    camera_config_id integer,
    name character varying(255) NOT NULL,
    description text,
    zone_type character varying(50) DEFAULT 'polygon'::character varying,
    coordinates jsonb NOT NULL,
    color character varying(20) DEFAULT '#FF0000'::character varying,
    is_active boolean DEFAULT true,
    trigger_on_enter boolean DEFAULT true,
    trigger_on_exit boolean DEFAULT false,
    trigger_on_stay boolean DEFAULT false,
    stay_threshold_seconds integer DEFAULT 5,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.roi_zones OWNER TO fyp_user;

--
-- Name: roi_zones_id_seq; Type: SEQUENCE; Schema: public; Owner: fyp_user
--

CREATE SEQUENCE public.roi_zones_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.roi_zones_id_seq OWNER TO fyp_user;

--
-- Name: roi_zones_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fyp_user
--

ALTER SEQUENCE public.roi_zones_id_seq OWNED BY public.roi_zones.id;


--
-- Name: scheduled_jobs; Type: TABLE; Schema: public; Owner: fyp_user
--

CREATE TABLE public.scheduled_jobs (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    camera_config_id integer,
    enabled_models jsonb DEFAULT '[]'::jsonb,
    model_configs jsonb DEFAULT '{}'::jsonb,
    cron_expression character varying(100) NOT NULL,
    duration_minutes integer,
    is_active boolean DEFAULT true,
    next_run_at timestamp with time zone,
    last_run_at timestamp with time zone,
    last_run_status character varying(50),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.scheduled_jobs OWNER TO fyp_user;

--
-- Name: scheduled_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: fyp_user
--

CREATE SEQUENCE public.scheduled_jobs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.scheduled_jobs_id_seq OWNER TO fyp_user;

--
-- Name: scheduled_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fyp_user
--

ALTER SEQUENCE public.scheduled_jobs_id_seq OWNED BY public.scheduled_jobs.id;


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: fyp_user
--

CREATE TABLE public.sessions (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    camera_source character varying(500) NOT NULL,
    status character varying(50) DEFAULT 'idle'::character varying,
    started_at timestamp with time zone DEFAULT now(),
    ended_at timestamp with time zone,
    config jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.sessions OWNER TO fyp_user;

--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: fyp_user
--

CREATE SEQUENCE public.sessions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sessions_id_seq OWNER TO fyp_user;

--
-- Name: sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fyp_user
--

ALTER SEQUENCE public.sessions_id_seq OWNED BY public.sessions.id;


--
-- Name: webhooks; Type: TABLE; Schema: public; Owner: fyp_user
--

CREATE TABLE public.webhooks (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    url character varying(500) NOT NULL,
    secret_key character varying(255),
    headers jsonb DEFAULT '{}'::jsonb,
    events jsonb DEFAULT '[]'::jsonb,
    is_active boolean DEFAULT true,
    retry_count integer DEFAULT 3,
    last_called_at timestamp with time zone,
    last_status_code integer,
    failure_count integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.webhooks OWNER TO fyp_user;

--
-- Name: webhooks_id_seq; Type: SEQUENCE; Schema: public; Owner: fyp_user
--

CREATE SEQUENCE public.webhooks_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.webhooks_id_seq OWNER TO fyp_user;

--
-- Name: webhooks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fyp_user
--

ALTER SEQUENCE public.webhooks_id_seq OWNED BY public.webhooks.id;


--
-- Name: activity_logs id; Type: DEFAULT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.activity_logs ALTER COLUMN id SET DEFAULT nextval('public.activity_logs_id_seq'::regclass);


--
-- Name: alert_rules id; Type: DEFAULT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.alert_rules ALTER COLUMN id SET DEFAULT nextval('public.alert_rules_id_seq'::regclass);


--
-- Name: camera_configs id; Type: DEFAULT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.camera_configs ALTER COLUMN id SET DEFAULT nextval('public.camera_configs_id_seq'::regclass);


--
-- Name: detection_results id; Type: DEFAULT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.detection_results ALTER COLUMN id SET DEFAULT nextval('public.detection_results_id_seq'::regclass);


--
-- Name: device_tokens id; Type: DEFAULT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.device_tokens ALTER COLUMN id SET DEFAULT nextval('public.device_tokens_id_seq'::regclass);


--
-- Name: pipeline_instances id; Type: DEFAULT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.pipeline_instances ALTER COLUMN id SET DEFAULT nextval('public.pipeline_instances_id_seq'::regclass);


--
-- Name: recordings id; Type: DEFAULT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.recordings ALTER COLUMN id SET DEFAULT nextval('public.recordings_id_seq'::regclass);


--
-- Name: roi_zones id; Type: DEFAULT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.roi_zones ALTER COLUMN id SET DEFAULT nextval('public.roi_zones_id_seq'::regclass);


--
-- Name: scheduled_jobs id; Type: DEFAULT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.scheduled_jobs ALTER COLUMN id SET DEFAULT nextval('public.scheduled_jobs_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.sessions ALTER COLUMN id SET DEFAULT nextval('public.sessions_id_seq'::regclass);


--
-- Name: webhooks id; Type: DEFAULT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.webhooks ALTER COLUMN id SET DEFAULT nextval('public.webhooks_id_seq'::regclass);


--
-- Data for Name: activity_logs; Type: TABLE DATA; Schema: public; Owner: fyp_user
--

COPY public.activity_logs (id, event_type, source, severity, message, pipeline_instance_id, session_id, metadata, created_at) FROM stdin;
3	update_instance_config	backend	error	Unexpected error updating config for instance 3: ActivityLogger.log_model_config_updated() missing 1 required positional argument: 'new_config'	\N	\N	{"new_config": {"yolo": {"target_classes": ["person", "car"], "confidence_threshold": 0.9}}, "instance_id": 3}	2026-03-24 18:25:48.377079+00
4	update_instance_config	backend	error	Unexpected error updating config for instance 3: ActivityLogger.log_info() missing 1 required positional argument: 'message'	\N	\N	{"new_config": {"yolo": {"nms_threshold": 0.4, "confidence_threshold": 0.75}}, "instance_id": 3}	2026-03-24 18:26:43.734148+00
6	instance_created	ml_manager	info	Pipeline instance 'Final Test Instance' created	4	\N	{"instance_name": "Final Test Instance", "enabled_models": ["yolo", "pose"], "camera_config_id": "0"}	2026-03-24 18:27:50.179071+00
7	instance_created	ml_manager	info	Pipeline instance 'Multi-Cam Test Instance' created	\N	\N	{"instance_name": "Multi-Cam Test Instance", "enabled_models": ["yolo"], "camera_config_id": "0"}	2026-03-24 18:59:13.328559+00
8	instance_started	ml_manager	info	Pipeline instance 5 started processing	\N	\N	{"camera_source": "Multi-Cam Test Instance"}	2026-03-24 18:59:21.694928+00
9	instance_stopped	ml_manager	info	Pipeline instance 5 stopped (Multi-Cam Test Instance frames)	\N	\N	{"reason": "manual", "frames_processed": "Multi-Cam Test Instance"}	2026-03-25 01:08:29.020345+00
13	instance_started	ml_manager	info	Pipeline instance 5 started processing	\N	\N	{"camera_source": "Multi-Cam Test Instance"}	2026-03-25 20:52:46.774058+00
14	instance_stopped	ml_manager	info	Pipeline instance 5 stopped (Multi-Cam Test Instance frames)	\N	\N	{"reason": "manual", "frames_processed": "Multi-Cam Test Instance"}	2026-03-25 20:54:07.797806+00
15	instance_started	ml_manager	info	Pipeline instance 5 started processing	\N	\N	{"camera_source": "Multi-Cam Test Instance"}	2026-03-25 20:54:09.0524+00
16	instance_deleted	backend	info	Pipeline instance 'Multi-Cam Test Instance' deleted	\N	\N	{"action": "delete", "instance_id": 5, "instance_name": "Multi-Cam Test Instance", "previous_status": "running"}	2026-03-25 20:55:06.300039+00
26	instance_stopped	ml_manager	info	Pipeline instance 4 stopped (Final Test Instance frames)	4	\N	{"reason": "manual", "frames_processed": "Final Test Instance"}	2026-03-26 02:11:10.171275+00
34	instance_started	ml_manager	info	Pipeline instance 4 started processing	4	\N	{"camera_source": "Final Test Instance"}	2026-03-26 02:16:13.544388+00
35	instance_paused	backend	info	Pipeline instance 'Final Test Instance' paused	4	\N	{"action": "pause", "old_status": "running"}	2026-03-26 02:16:19.367925+00
36	instance_started	ml_manager	info	Pipeline instance 4 started processing	4	\N	{"camera_source": "Final Test Instance"}	2026-03-26 02:16:24.409801+00
37	instance_stopped	ml_manager	info	Pipeline instance 4 stopped (Final Test Instance frames)	4	\N	{"reason": "manual", "frames_processed": "Final Test Instance"}	2026-03-26 02:16:30.095133+00
1	instance_created	ml_manager	info	Pipeline instance 'Test Logging Instance' created	\N	\N	{"instance_name": "Test Logging Instance", "enabled_models": ["yolo"], "camera_config_id": "0"}	2026-03-24 18:23:58.71461+00
17	instance_created	ml_manager	info	Pipeline instance 'Recording E2E Instance' created	\N	\N	{"instance_name": "Recording E2E Instance", "enabled_models": ["yolo"], "camera_config_id": "/videos/test_pose_video.mp4"}	2026-03-25 20:55:07.562374+00
18	instance_started	ml_manager	info	Pipeline instance 6 started processing	\N	\N	{"camera_source": "Recording E2E Instance"}	2026-03-25 20:55:07.618727+00
19	instance_paused	backend	info	Pipeline instance 'Recording E2E Instance' paused	\N	\N	{"action": "pause", "old_status": "running"}	2026-03-26 01:49:08.782352+00
20	instance_resumed	backend	info	Pipeline instance 'Recording E2E Instance' resumed	\N	\N	{"action": "resume", "old_status": "paused"}	2026-03-26 01:49:31.705872+00
21	instance_paused	backend	info	Pipeline instance 'Recording E2E Instance' paused	\N	\N	{"action": "pause", "old_status": "running"}	2026-03-26 01:49:35.730275+00
22	instance_started	ml_manager	info	Pipeline instance 6 started processing	\N	\N	{"camera_source": "Recording E2E Instance"}	2026-03-26 01:50:35.524716+00
23	instance_stopped	ml_manager	info	Pipeline instance 6 stopped (Recording E2E Instance frames)	\N	\N	{"reason": "manual", "frames_processed": "Recording E2E Instance"}	2026-03-26 01:51:02.631353+00
25	instance_stopped	ml_manager	info	Pipeline instance 6 stopped (Recording E2E Instance frames)	\N	\N	{"reason": "manual", "frames_processed": "Recording E2E Instance"}	2026-03-26 02:11:10.122992+00
29	instance_started	ml_manager	info	Pipeline instance 6 started processing	\N	\N	{"camera_source": "Recording E2E Instance"}	2026-03-26 02:11:24.640658+00
31	instance_stopped	ml_manager	info	Pipeline instance 6 stopped (Recording E2E Instance frames)	\N	\N	{"reason": "manual", "frames_processed": "Recording E2E Instance"}	2026-03-26 02:15:11.640276+00
33	instance_started	ml_manager	info	Pipeline instance 6 started processing	\N	\N	{"camera_source": "Recording E2E Instance"}	2026-03-26 02:16:02.782796+00
38	instance_started	ml_manager	info	Pipeline instance 4 started processing	4	\N	{"camera_source": "Final Test Instance"}	2026-03-26 02:16:32.7051+00
40	instance_stopped	ml_manager	info	Pipeline instance 4 stopped (Final Test Instance frames)	4	\N	{"reason": "manual", "frames_processed": "Final Test Instance"}	2026-03-26 02:16:55.7383+00
42	instance_resumed	backend	info	Pipeline instance 'Final Test Instance' resumed	4	\N	{"action": "resume", "old_status": "stopped"}	2026-03-26 02:21:07.773538+00
28	instance_stopped	ml_manager	info	Pipeline instance 1 stopped (Camera 1 Instance frames)	\N	\N	{"reason": "manual", "frames_processed": "Camera 1 Instance"}	2026-03-26 02:11:10.2129+00
44	instance_resumed	backend	info	Pipeline instance 'Camera 1 Instance' resumed	\N	\N	{"action": "resume", "old_status": "stopped"}	2026-03-26 02:21:07.856153+00
45	instance_deleted	backend	info	Pipeline instance 'Camera 1 Instance' deleted	\N	\N	{"action": "delete", "instance_id": 1, "instance_name": "Camera 1 Instance", "previous_status": "running"}	2026-03-26 02:21:14.118164+00
2	instance_started	ml_manager	info	Pipeline instance 3 started processing	\N	\N	{"camera_source": "Test Logging Instance"}	2026-03-24 18:24:06.995812+00
5	config_updated	backend	info	Pipeline instance 'Test Logging Instance' configuration updated: yolo.confidence_threshold: 0.85 ÔåÆ 0.85	\N	\N	{"new_config": {"yolo": {"confidence_threshold": 0.85}}, "old_config": {"yolo": {"nms_threshold": 0.4, "target_classes": ["person", "car"], "confidence_threshold": 0.85}}}	2026-03-24 18:27:38.861283+00
10	instance_stopped	ml_manager	info	Pipeline instance 3 stopped (Test Logging Instance frames)	\N	\N	{"reason": "manual", "frames_processed": "Test Logging Instance"}	2026-03-25 01:08:29.504772+00
11	instance_started	ml_manager	info	Pipeline instance 3 started processing	\N	\N	{"camera_source": "Test Logging Instance"}	2026-03-25 01:18:05.032932+00
12	instance_started	ml_manager	info	Pipeline instance 3 started processing	\N	\N	{"camera_source": "Test Logging Instance"}	2026-03-25 04:54:05.443048+00
24	instance_stopped	ml_manager	info	Pipeline instance 3 stopped (Test Logging Instance frames)	\N	\N	{"reason": "manual", "frames_processed": "Test Logging Instance"}	2026-03-26 01:51:06.538347+00
27	instance_stopped	ml_manager	info	Pipeline instance 3 stopped (Test Logging Instance frames)	\N	\N	{"reason": "manual", "frames_processed": "Test Logging Instance"}	2026-03-26 02:11:10.190119+00
30	instance_started	ml_manager	info	Pipeline instance 3 started processing	\N	\N	{"camera_source": "Test Logging Instance"}	2026-03-26 02:13:35.635077+00
32	instance_stopped	ml_manager	info	Pipeline instance 3 stopped (Test Logging Instance frames)	\N	\N	{"reason": "manual", "frames_processed": "Test Logging Instance"}	2026-03-26 02:15:11.667217+00
43	instance_resumed	backend	info	Pipeline instance 'Test Logging Instance' resumed	\N	\N	{"action": "resume", "old_status": "stopped"}	2026-03-26 02:21:07.814946+00
46	instance_deleted	backend	info	Pipeline instance 'Test Logging Instance' deleted	\N	\N	{"action": "delete", "instance_id": 3, "instance_name": "Test Logging Instance", "previous_status": "running"}	2026-03-26 02:21:18.021646+00
47	instance_paused	backend	info	Pipeline instance 'Final Test Instance' paused	4	\N	{"action": "pause", "old_status": "running"}	2026-03-26 02:21:20.69171+00
48	instance_stopped	ml_manager	info	Pipeline instance 4 stopped (Final Test Instance frames)	4	\N	{"reason": "manual", "frames_processed": "Final Test Instance"}	2026-03-26 02:21:22.044686+00
74	update_instance_config	backend	error	Pipeline instance 3 not found for config update	\N	\N	{"new_config": {"yolo": {"confidence": 0.65, "nms_threshold": 0.45}}, "instance_id": 3}	2026-04-18 15:25:49.179042+00
39	instance_stopped	ml_manager	info	Pipeline instance 6 stopped (Recording E2E Instance frames)	\N	\N	{"reason": "manual", "frames_processed": "Recording E2E Instance"}	2026-03-26 02:16:47.264597+00
41	instance_resumed	backend	info	Pipeline instance 'Recording E2E Instance' resumed	\N	\N	{"action": "resume", "old_status": "stopped"}	2026-03-26 02:21:07.737069+00
49	instance_stopped	ml_manager	info	Pipeline instance 6 stopped (Recording E2E Instance frames)	\N	\N	{"reason": "manual", "frames_processed": "Recording E2E Instance"}	2026-03-26 02:21:25.59954+00
75	config_updated	backend	info	Pipeline instance 'Recording E2E Instance' configuration updated: yolo.confidence: 0.65 ÔåÆ 0.65, yolo.nms_threshold: 0.45 ÔåÆ 0.45	\N	\N	{"new_config": {"yolo": {"confidence": 0.65, "nms_threshold": 0.45}}, "old_config": {"yolo": {"confidence": 0.65, "nms_threshold": 0.45, "confidence_threshold": 0.6}}}	2026-04-18 15:26:03.524434+00
76	instance_deleted	backend	info	Pipeline instance 'Recording E2E Instance' deleted	\N	\N	{"action": "delete", "instance_id": 6, "instance_name": "Recording E2E Instance", "previous_status": "stopped"}	2026-04-19 06:35:00.594088+00
77	instance_stopped	ml_manager	info	Pipeline instance 4 stopped (Final Test Instance frames)	4	\N	{"reason": "manual", "frames_processed": "Final Test Instance"}	2026-04-19 12:14:26.400318+00
\.


--
-- Data for Name: alert_rules; Type: TABLE DATA; Schema: public; Owner: fyp_user
--

COPY public.alert_rules (id, name, description, pipeline_instance_id, model_name, trigger_condition, actions, is_active, cooldown_seconds, trigger_count, last_triggered_at, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: camera_configs; Type: TABLE DATA; Schema: public; Owner: fyp_user
--

COPY public.camera_configs (id, name, source_type, source_url, fps, width, height, is_default, created_at, group_name, enabled_models, model_configs) FROM stdin;
\.


--
-- Data for Name: detection_results; Type: TABLE DATA; Schema: public; Owner: fyp_user
--

COPY public.detection_results (id, session_id, frame_id, "timestamp", model_name, result_data, confidence, processing_time_ms) FROM stdin;
\.


--
-- Data for Name: device_tokens; Type: TABLE DATA; Schema: public; Owner: fyp_user
--

COPY public.device_tokens (id, user_id, device_token, platform, device_name, is_active, last_used_at, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: pipeline_instances; Type: TABLE DATA; Schema: public; Owner: fyp_user
--

COPY public.pipeline_instances (id, session_id, camera_config_id, name, status, enabled_models, model_configs, fps, frames_processed, last_error, created_at, updated_at) FROM stdin;
4	\N	\N	Final Test Instance	stopped	["yolo", "pose"]	{"pose": {"confidence_threshold": 0.5}, "yolo": {"confidence_threshold": 0.6}}	0	0	\N	2026-03-24 18:27:50.160886+00	2026-03-26 02:21:22.03563+00
\.


--
-- Data for Name: recordings; Type: TABLE DATA; Schema: public; Owner: fyp_user
--

COPY public.recordings (id, session_id, pipeline_instance_id, name, file_path, results_file_path, file_size_bytes, duration_seconds, fps, width, height, codec, frame_count, status, started_at, ended_at, created_at) FROM stdin;
2	\N	\N	e2e_1774471996142	/videos/recordings/e2e_1774471996142.mp4	\N	\N	3.563412	\N	\N	\N	\N	\N	completed	2026-03-25 20:53:16.08511+00	2026-03-25 20:53:19.648522+00	2026-03-25 20:53:16.08511+00
3	\N	\N	e2e_file_1774472051336	/videos/recordings/e2e_file_1774472051336.mp4	\N	\N	4.527234	\N	\N	\N	\N	\N	completed	2026-03-25 20:54:11.332455+00	2026-03-25 20:54:15.859689+00	2026-03-25 20:54:11.332455+00
4	\N	\N	recording_e2e_1774472110149	/videos/recordings/recording_e2e_1774472110149.mp4	\N	378589	5.0943121910095215	15.551639967860615	640	480	mp4v	71	completed	2026-03-25 20:55:10.150067+00	2026-03-25 20:55:15.234195+00	2026-03-25 20:55:10.150067+00
\.


--
-- Data for Name: roi_zones; Type: TABLE DATA; Schema: public; Owner: fyp_user
--

COPY public.roi_zones (id, camera_config_id, name, description, zone_type, coordinates, color, is_active, trigger_on_enter, trigger_on_exit, trigger_on_stay, stay_threshold_seconds, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: scheduled_jobs; Type: TABLE DATA; Schema: public; Owner: fyp_user
--

COPY public.scheduled_jobs (id, name, description, camera_config_id, enabled_models, model_configs, cron_expression, duration_minutes, is_active, next_run_at, last_run_at, last_run_status, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: sessions; Type: TABLE DATA; Schema: public; Owner: fyp_user
--

COPY public.sessions (id, name, camera_source, status, started_at, ended_at, config, created_at) FROM stdin;
1	Session http://192.168.1.208:4747	http://192.168.1.208:4747	running	2026-03-15 18:44:43.812145+00	\N	{}	2026-03-15 18:44:43.812145+00
2	Session http://192.168.1.208:4747/video	http://192.168.1.208:4747/video	running	2026-03-15 18:46:26.906752+00	\N	{}	2026-03-15 18:46:26.906752+00
3	Session http://192.168.1.208:4747/video	http://192.168.1.208:4747/video	running	2026-03-15 18:46:33.718376+00	\N	{}	2026-03-15 18:46:33.718376+00
4	Session http://192.168.1.208:4747/video	http://192.168.1.208:4747/video	running	2026-03-15 18:46:54.511531+00	\N	{}	2026-03-15 18:46:54.511531+00
5	Session http://192.168.1.208:4747/video	http://192.168.1.208:4747/video	running	2026-03-15 18:48:12.498848+00	\N	{}	2026-03-15 18:48:12.498848+00
6	Session /videos/test_pose_video.mp4	/videos/test_pose_video.mp4	running	2026-03-24 13:14:45.848142+00	\N	{}	2026-03-24 13:14:45.848142+00
7	Session http://192.168.1.208:4747	http://192.168.1.208:4747	running	2026-03-24 13:16:06.547163+00	\N	{}	2026-03-24 13:16:06.547163+00
8	Session http://192.168.1.208:4747	http://192.168.1.208:4747	running	2026-03-24 13:16:21.164249+00	\N	{}	2026-03-24 13:16:21.164249+00
9	Session http://192.168.1.208:4747	http://192.168.1.208:4747	running	2026-03-24 13:16:24.931364+00	\N	{}	2026-03-24 13:16:24.931364+00
10	Session http://192.168.1.208:4747/video	http://192.168.1.208:4747/video	running	2026-03-24 13:16:31.862089+00	\N	{}	2026-03-24 13:16:31.862089+00
11	Session http://192.168.1.208:4747/video	http://192.168.1.208:4747/video	running	2026-03-24 13:16:32.652066+00	\N	{}	2026-03-24 13:16:32.652066+00
12	Session http://192.168.1.208:4747/video	http://192.168.1.208:4747/video	running	2026-03-24 13:16:46.689886+00	\N	{}	2026-03-24 13:16:46.689886+00
13	Session http://192.168.1.208:4747/video	http://192.168.1.208:4747/video	running	2026-03-24 13:17:39.905605+00	\N	{}	2026-03-24 13:17:39.905605+00
14	Session http://192.168.1.208:4747/video	http://192.168.1.208:4747/video	running	2026-03-24 13:19:47.961075+00	\N	{}	2026-03-24 13:19:47.961075+00
15	Session http://192.168.1.208:4747/video	http://192.168.1.208:4747/video	running	2026-03-24 14:47:56.762884+00	\N	{}	2026-03-24 14:47:56.762884+00
16	Session http://192.168.1.208:4747/video	http://192.168.1.208:4747/video	running	2026-03-24 14:48:34.688381+00	\N	{}	2026-03-24 14:48:34.688381+00
17	Scheduled: auto_schedule_1774477225355	/videos/test_pose_video.mp4	running	2026-03-25 22:20:35.226346+00	\N	{"model_configs": {}, "enabled_models": ["yolo"], "cron_expression": "*/5 * * * *", "schedule_job_id": 2}	2026-03-25 22:20:35.226346+00
18	Session 0	0	running	2026-04-18 17:08:13.198358+00	\N	{}	2026-04-18 17:08:13.198358+00
19	Session 0	0	running	2026-04-19 12:14:22.021476+00	\N	{}	2026-04-19 12:14:22.021476+00
20	Session 0	0	running	2026-04-19 12:24:11.696475+00	\N	{}	2026-04-19 12:24:11.696475+00
21	Session 0	0	running	2026-04-19 12:25:14.223815+00	\N	{}	2026-04-19 12:25:14.223815+00
22	Session 0	0	running	2026-04-19 12:29:49.200824+00	\N	{}	2026-04-19 12:29:49.200824+00
23	Session /videos/recordings/recording_e2e_1774472110149.mp4	/videos/recordings/recording_e2e_1774472110149.mp4	running	2026-04-19 12:34:40.850555+00	\N	{}	2026-04-19 12:34:40.850555+00
24	Session /videos/recordings/recording_e2e_1774472110149.mp4	/videos/recordings/recording_e2e_1774472110149.mp4	running	2026-04-19 12:39:20.980958+00	\N	{}	2026-04-19 12:39:20.980958+00
25	Session /videos/recordings/recording_e2e_1774472110149.mp4	/videos/recordings/recording_e2e_1774472110149.mp4	running	2026-04-19 12:40:13.297982+00	\N	{}	2026-04-19 12:40:13.297982+00
26	Session /videos/recordings/recording_e2e_1774472110149.mp4	/videos/recordings/recording_e2e_1774472110149.mp4	running	2026-04-19 12:40:42.000922+00	\N	{}	2026-04-19 12:40:42.000922+00
27	Session /videos/recordings/recording_e2e_1774472110149.mp4	/videos/recordings/recording_e2e_1774472110149.mp4	running	2026-04-19 12:41:11.732415+00	\N	{}	2026-04-19 12:41:11.732415+00
28	Session /videos/recordings/recording_e2e_1774472110149.mp4	/videos/recordings/recording_e2e_1774472110149.mp4	running	2026-04-19 12:41:42.485589+00	\N	{}	2026-04-19 12:41:42.485589+00
29	Session /videos/recordings/recording_e2e_1774472110149.mp4	/videos/recordings/recording_e2e_1774472110149.mp4	running	2026-04-19 12:46:31.345366+00	\N	{}	2026-04-19 12:46:31.345366+00
30	Session /videos/recordings/recording_e2e_1774472110149.mp4	/videos/recordings/recording_e2e_1774472110149.mp4	running	2026-04-19 12:47:19.595968+00	\N	{}	2026-04-19 12:47:19.595968+00
31	Session /videos/recordings/recording_e2e_1774472110149.mp4	/videos/recordings/recording_e2e_1774472110149.mp4	running	2026-04-19 12:47:58.965324+00	\N	{}	2026-04-19 12:47:58.965324+00
\.


--
-- Data for Name: webhooks; Type: TABLE DATA; Schema: public; Owner: fyp_user
--

COPY public.webhooks (id, name, url, secret_key, headers, events, is_active, retry_count, last_called_at, last_status_code, failure_count, created_at, updated_at) FROM stdin;
\.


--
-- Name: activity_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fyp_user
--

SELECT pg_catalog.setval('public.activity_logs_id_seq', 77, true);


--
-- Name: alert_rules_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fyp_user
--

SELECT pg_catalog.setval('public.alert_rules_id_seq', 1, true);


--
-- Name: camera_configs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fyp_user
--

SELECT pg_catalog.setval('public.camera_configs_id_seq', 2, true);


--
-- Name: detection_results_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fyp_user
--

SELECT pg_catalog.setval('public.detection_results_id_seq', 1, false);


--
-- Name: device_tokens_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fyp_user
--

SELECT pg_catalog.setval('public.device_tokens_id_seq', 2, true);


--
-- Name: pipeline_instances_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fyp_user
--

SELECT pg_catalog.setval('public.pipeline_instances_id_seq', 6, true);


--
-- Name: recordings_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fyp_user
--

SELECT pg_catalog.setval('public.recordings_id_seq', 4, true);


--
-- Name: roi_zones_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fyp_user
--

SELECT pg_catalog.setval('public.roi_zones_id_seq', 1, true);


--
-- Name: scheduled_jobs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fyp_user
--

SELECT pg_catalog.setval('public.scheduled_jobs_id_seq', 2, true);


--
-- Name: sessions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fyp_user
--

SELECT pg_catalog.setval('public.sessions_id_seq', 31, true);


--
-- Name: webhooks_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fyp_user
--

SELECT pg_catalog.setval('public.webhooks_id_seq', 1, true);


--
-- Name: activity_logs activity_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.activity_logs
    ADD CONSTRAINT activity_logs_pkey PRIMARY KEY (id);


--
-- Name: alert_rules alert_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.alert_rules
    ADD CONSTRAINT alert_rules_pkey PRIMARY KEY (id);


--
-- Name: camera_configs camera_configs_name_key; Type: CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.camera_configs
    ADD CONSTRAINT camera_configs_name_key UNIQUE (name);


--
-- Name: camera_configs camera_configs_pkey; Type: CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.camera_configs
    ADD CONSTRAINT camera_configs_pkey PRIMARY KEY (id);


--
-- Name: detection_results detection_results_pkey; Type: CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.detection_results
    ADD CONSTRAINT detection_results_pkey PRIMARY KEY (id);


--
-- Name: device_tokens device_tokens_device_token_key; Type: CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.device_tokens
    ADD CONSTRAINT device_tokens_device_token_key UNIQUE (device_token);


--
-- Name: device_tokens device_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.device_tokens
    ADD CONSTRAINT device_tokens_pkey PRIMARY KEY (id);


--
-- Name: pipeline_instances pipeline_instances_pkey; Type: CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.pipeline_instances
    ADD CONSTRAINT pipeline_instances_pkey PRIMARY KEY (id);


--
-- Name: recordings recordings_pkey; Type: CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.recordings
    ADD CONSTRAINT recordings_pkey PRIMARY KEY (id);


--
-- Name: roi_zones roi_zones_pkey; Type: CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.roi_zones
    ADD CONSTRAINT roi_zones_pkey PRIMARY KEY (id);


--
-- Name: scheduled_jobs scheduled_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.scheduled_jobs
    ADD CONSTRAINT scheduled_jobs_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: webhooks webhooks_pkey; Type: CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.webhooks
    ADD CONSTRAINT webhooks_pkey PRIMARY KEY (id);


--
-- Name: idx_activity_logs_created; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_activity_logs_created ON public.activity_logs USING btree (created_at DESC);


--
-- Name: idx_activity_logs_pipeline; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_activity_logs_pipeline ON public.activity_logs USING btree (pipeline_instance_id);


--
-- Name: idx_activity_logs_severity; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_activity_logs_severity ON public.activity_logs USING btree (severity);


--
-- Name: idx_activity_logs_type; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_activity_logs_type ON public.activity_logs USING btree (event_type);


--
-- Name: idx_alert_rules_active; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_alert_rules_active ON public.alert_rules USING btree (is_active);


--
-- Name: idx_alert_rules_pipeline; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_alert_rules_pipeline ON public.alert_rules USING btree (pipeline_instance_id);


--
-- Name: idx_device_tokens_active; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_device_tokens_active ON public.device_tokens USING btree (is_active);


--
-- Name: idx_pipeline_instances_camera; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_pipeline_instances_camera ON public.pipeline_instances USING btree (camera_config_id);


--
-- Name: idx_pipeline_instances_session; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_pipeline_instances_session ON public.pipeline_instances USING btree (session_id);


--
-- Name: idx_pipeline_instances_status; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_pipeline_instances_status ON public.pipeline_instances USING btree (status);


--
-- Name: idx_recordings_pipeline; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_recordings_pipeline ON public.recordings USING btree (pipeline_instance_id);


--
-- Name: idx_recordings_session; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_recordings_session ON public.recordings USING btree (session_id);


--
-- Name: idx_recordings_status; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_recordings_status ON public.recordings USING btree (status);


--
-- Name: idx_results_frame; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_results_frame ON public.detection_results USING btree (session_id, frame_id);


--
-- Name: idx_results_model; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_results_model ON public.detection_results USING btree (model_name);


--
-- Name: idx_results_session; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_results_session ON public.detection_results USING btree (session_id);


--
-- Name: idx_roi_zones_active; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_roi_zones_active ON public.roi_zones USING btree (is_active);


--
-- Name: idx_roi_zones_camera; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_roi_zones_camera ON public.roi_zones USING btree (camera_config_id);


--
-- Name: idx_scheduled_jobs_active; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_scheduled_jobs_active ON public.scheduled_jobs USING btree (is_active);


--
-- Name: idx_scheduled_jobs_next_run; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_scheduled_jobs_next_run ON public.scheduled_jobs USING btree (next_run_at);


--
-- Name: idx_sessions_status; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_sessions_status ON public.sessions USING btree (status);


--
-- Name: idx_webhooks_active; Type: INDEX; Schema: public; Owner: fyp_user
--

CREATE INDEX idx_webhooks_active ON public.webhooks USING btree (is_active);


--
-- Name: activity_logs activity_logs_pipeline_instance_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.activity_logs
    ADD CONSTRAINT activity_logs_pipeline_instance_id_fkey FOREIGN KEY (pipeline_instance_id) REFERENCES public.pipeline_instances(id) ON DELETE SET NULL;


--
-- Name: activity_logs activity_logs_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.activity_logs
    ADD CONSTRAINT activity_logs_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.sessions(id) ON DELETE SET NULL;


--
-- Name: alert_rules alert_rules_pipeline_instance_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.alert_rules
    ADD CONSTRAINT alert_rules_pipeline_instance_id_fkey FOREIGN KEY (pipeline_instance_id) REFERENCES public.pipeline_instances(id) ON DELETE CASCADE;


--
-- Name: detection_results detection_results_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.detection_results
    ADD CONSTRAINT detection_results_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.sessions(id) ON DELETE CASCADE;


--
-- Name: pipeline_instances pipeline_instances_camera_config_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.pipeline_instances
    ADD CONSTRAINT pipeline_instances_camera_config_id_fkey FOREIGN KEY (camera_config_id) REFERENCES public.camera_configs(id) ON DELETE SET NULL;


--
-- Name: pipeline_instances pipeline_instances_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.pipeline_instances
    ADD CONSTRAINT pipeline_instances_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.sessions(id) ON DELETE CASCADE;


--
-- Name: recordings recordings_pipeline_instance_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.recordings
    ADD CONSTRAINT recordings_pipeline_instance_id_fkey FOREIGN KEY (pipeline_instance_id) REFERENCES public.pipeline_instances(id) ON DELETE SET NULL;


--
-- Name: recordings recordings_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.recordings
    ADD CONSTRAINT recordings_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.sessions(id) ON DELETE CASCADE;


--
-- Name: roi_zones roi_zones_camera_config_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.roi_zones
    ADD CONSTRAINT roi_zones_camera_config_id_fkey FOREIGN KEY (camera_config_id) REFERENCES public.camera_configs(id) ON DELETE CASCADE;


--
-- Name: scheduled_jobs scheduled_jobs_camera_config_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: fyp_user
--

ALTER TABLE ONLY public.scheduled_jobs
    ADD CONSTRAINT scheduled_jobs_camera_config_id_fkey FOREIGN KEY (camera_config_id) REFERENCES public.camera_configs(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict CULHl1YdyPgubfzcgl6xr7bKlcxUaw5R7tuNlb8UCJ1zqEHZnCYG5FFINdwAsW6

