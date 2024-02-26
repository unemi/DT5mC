//
//  MyAgent.h
//  DT5

@import Cocoa;
@import simd;
#define AgentWeight .004

typedef struct TrailCell {
	struct TrailCell *prev, *post;
	simd_float2 p;
	float l;
} TrailCell;

typedef struct  {
	simd_float2 p, v;
	TrailCell *head, *tail;
	float leftLife, length;
	uint32 trailCount;
	float atrct;
} MyAgent;

typedef struct {
	MyAgent *a;
	NSInteger nAgents;
	simd_float2 *vx;
	uint16 *idx;
	float *op;
} AgentVecInfo;

extern void setup_agents(void);
extern void change_n_agents(void);
extern void reset_agents(void);
extern void exocrine_agents(void);
extern void move_agents(float elapsed);
extern void agent_vectors(simd_float2 *vx, uint16 *idx, float *op,
	void (^set_metal_com)(NSInteger, NSInteger, NSInteger));
extern void copy_swarm_in_PDF(void);
