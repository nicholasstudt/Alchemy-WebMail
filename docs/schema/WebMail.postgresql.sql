/*
 * Postgresql schema file for Alchemy::WebMail.
 * $Date: 2004/06/24 02:59:08 $
 */


create sequence "wm_users_seq";
create table "wm_users" (
	id 					int4 PRIMARY KEY DEFAULT NEXTVAL( 'wm_users_seq' ),
	reply_include		bool,		/* include original in reply */
	true_delete			bool,		/* True means no trash */
	session_length		int4,		/* length of users session */
	fldr_showcount		int2,		/* number of emails in folder to show */
	fldr_sortorder		int2,		/* folder sort order */
	fldr_sortfield		varchar,	/* folder sort field */
	username			varchar 	/* imap user name */
);

create sequence "wm_roles_seq";
create table "wm_roles" (
	id 			int4 PRIMARY KEY DEFAULT NEXTVAL( 'wm_roles_seq' ),
	wm_user_id	int4,		/* user entry id ( wm_users.id ) */
	main_role	bool,		/* only one default allowed per user */
	role_name	varchar, 	/* name of the role */
	name		varchar, 	/* name to display in email */
	reply_to	varchar, 	/* reply to email address */
	savesent	varchar, 	/* folder to save sent into */
	signature	text 		/* Role signature */
);

create sequence "wm_abook_seq";
create table "wm_abook" (
	id 			int4 PRIMARY KEY DEFAULT NEXTVAL( 'wm_abook_seq' ),
	wm_user_id	int4,		/* user entry id ( wm_users.id ) */
	first_name	varchar,	/* first name */
	last_name	varchar,	/* last name */
	email		varchar		/* email address */
);

create sequence "wm_mlist_seq";
create table "wm_mlist" (
	id 			int4 PRIMARY KEY DEFAULT NEXTVAL( 'wm_mlist_seq' ),
	wm_user_id	int4,		/* user entry id ( wm_users.id ) */
	name		varchar		/* group name */
);

create table "wm_mlist_members" (
	wm_user_id	int4,		/* user entry id ( wm_users.id ) */
	wm_mlist_id int4,		/* maililng list entry id */
	wm_abook_id int4		/* address book entry id */
);
