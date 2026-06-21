#version 400 compatibility
#ifndef MC_OS_MAC
#extension GL_ARB_shader_image_load_store : enable
#endif
#define WORLD_NETHER
#define PROGRAM_SHADOW
#define PROGRAM_SHADOW_SOLID
#define vsh
#include "/program/shadow.vsh"
