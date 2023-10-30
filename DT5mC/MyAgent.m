//
//  MyAgent.m
//  DT5

#import "Communication.h"
#import "MyAgent.h"
#import "Controller2.h"
#import "Display.h"
#define InitV .002
#define MaxV 8.
#define AttractantTh3 0.05f
#define AgentWeight .004
#define AgentLength .0333
#define TurnAngle (M_PI/2)
#define MaxWarp .2
#define AllocUnit 4096

static MyAgent *theAgents = NULL;
static NSLock *TrailMemLock, *AgentTrailLock;
static TrailCell *TrailMem = NULL;
static NSInteger nThreads = 1;
static NSOperationQueue *opeQue = nil;

static TrailCell *newTrailCell(simd_float2 p, float l) {
	[TrailMemLock lock];
	if (TrailMem == NULL) {
		TrailMem = malloc(sizeof(TrailCell) * AllocUnit);
		if (TrailMem == NULL) {
			error_msg(@"Could not allocate memory for Trail Cells.", 0);
			return NULL;
		}
		for (NSInteger i = 0; i < AllocUnit-1; i ++)
			TrailMem[i].post = TrailMem + i + 1;
		TrailMem[AllocUnit-1].post = NULL;
	}
	TrailCell *newMem = TrailMem;
	TrailMem = newMem->post;
	[TrailMemLock unlock];
	newMem->p = p;
	newMem->l = l;
	newMem->prev = newMem->post = NULL;
	return newMem;
}
static void removeTrailCell(TrailCell *tc) {
	if (tc->prev) tc->prev->post = tc->post;
	if (tc->post) tc->post->prev = tc->prev;
	[TrailMemLock lock];
	tc->post = TrailMem;
	TrailMem = tc;
	[TrailMemLock unlock];
}
static void discardTrailCells(TrailCell *head, TrailCell *tail) {
	[TrailMemLock lock];
	tail->post = TrailMem;
	TrailMem = head;
	[TrailMemLock unlock];
}

#define Dist2(x, y) ((x) * (x) + (y) * (y))
#define SumValue(u, v) { sumw += (ww = (cos(sqrt(ww) / M_PI) + 1.) / 2.);\
	sum += ww * map[v * FrameWidth + u]; }
static float get_chem(float *map, simd_float2 q) {
	simd_int2 ij = simd_int_rte(floor(q));
	if (ij.x < 0 || ij.y < 0 || ij.x >= FrameWidth || ij.y >= FrameHeight) return 0.f;
	simd_float2 d = q - ij - .5;
	simd_int2 dij = {(d.x < 0.)? -1 : 1, (d.y < 0)? -1 : 1};
	simd_float2 dd = (simd_float2){1., 1.} - dij * d;
	simd_int2 ii = simd_clamp(ij + dij,
		(simd_int2){0, 0}, (simd_int2){FrameWidth-1, FrameHeight-1});
	float ww, sumw, sum;
	sum = (sumw = 1 - simd_length_squared(d)) * map[ij.y * FrameWidth + ij.x];
	if ((ww = Dist2(d.x, dd.y)) < 1) SumValue(ij.x, ii.y)
	if ((ww = Dist2(dd.x, d.y)) < 1) SumValue(ii.x, ij.y)
	if ((ww = Dist2(dd.x, dd.y)) < 1) SumValue(ii.x, ii.y)
	return sum / sumw;
}
static float get_chemical(float *map, simd_float2 p) {
	return get_chem(map, p * (simd_float2){FrameWidth / camXMax, FrameHeight});
}
static BOOL random_bool(void) {
//	static unsigned long n, k = 0;
	static NSInteger n, k = 0;
	if (k <= 0) { k = 32; n = lrand48(); }
	else { k --; n >>= 1; }
	return ((n & 1) == 1);
}
static void reset_agent(MyAgent *a) {
	CGFloat size = AgentWeight * agentWeight;
	a->p.y = drand48() * (1 + camXMax) * 2;
	if (a->p.y < 1) { a->p.x = -size; a->v.x = InitV; a->v.y = 0; }
	else if (a->p.y < 1 + camXMax)
		{ a->p.x = a->p.y - 1; a->p.y = 1+size; a->v.x = 0; a->v.y = -InitV; }
	else if (a->p.y < 2 + camXMax)
		{ a->p.x = camXMax+size; a->p.y -= 1 + camXMax; a->v.x = -InitV; a->v.y = 0; }
	else { a->p.x = a->p.y - 2 - camXMax; a->p.y = -size; a->v.x = 0; a->v.y = InitV; }
	if (a->head != NULL) discardTrailCells(a->head, a->tail);
	a->head = a->tail = newTrailCell(a->p, 0.);
	a->length = 0.;
	a->trailCount = 1;
	a->leftLife = drand48() * 5.;
}
static void warp_agent(MyAgent *a) {
	simd_float2 leftBottom = {a->p.x, a->p.y}, rightTop = {a->p.x, a->p.y};
	for (TrailCell *tc = a->head; tc; tc = tc->post) {
		leftBottom = simd_min(leftBottom, tc->p);
		rightTop = simd_max(rightTop, tc->p);
	}
	simd_float2 sz = rightTop - leftBottom,
		d = {drand48() * (camXMax - sz.x), drand48() * (1. - sz.y)};
	d -= leftBottom;
	a->p += d;
	for (TrailCell *tc = a->head; tc; tc = tc->post) tc->p += d;
	a->leftLife = 5.;
}
static void exocrine_agent(MyAgent *a) {
	simd_int2 ij = simd_int_sat(a->p * (simd_float2){FrameWidth / camXMax, FrameHeight});
	if (ij.x >= 0 && ij.y >= 0 && ij.x < FrameWidth && ij.y < FrameHeight)
		RplntSrcMap[ij.y * FrameWidth + ij.x] = 1.;
}
static float elapsedSec = 0.;
static void move_agent(MyAgent *a) {
	if ((a->leftLife -= elapsedSec) <= 0.) warp_agent(a);
	float bAngle = agentTurnAngle * TurnAngle * (drand48() + .5);
	float bVelocity = InitV * (drand48() * 1.2 + .3);
	float atrct = get_chemical(AtrctSrcMap, a->p);
	if (atrct > thHiSpeed) bVelocity *= agentSpeed;
	else if (atrct > thHiSpeed / 2) bVelocity *=
		1. + (thHiSpeed / 2 - atrct) / thHiSpeed * 2 * (1. - agentSpeed);
	else bVelocity *= atrct / thHiSpeed * 2 + (1. - atrct / thHiSpeed * 2) * MaxV;
	if (bVelocity <= 0.) return;
	float ph[3], th = atan2(a->v.y, a->v.x), s = 0.;
	simd_float2 candidate[3];
	for (int i = 0; i < 3; i ++) {
		float phi = th + (i - 1) * bAngle;
		simd_float2 sp = candidate[i] = a->p + bVelocity * (simd_float2){cos(phi), sin(phi)};
		ph[i] = get_chemical(AtrctSrcMap, sp)
			- avoidance * pow(get_chemical(RplntSrcMap, sp), 2.f);
		s += ph[i];
	}
	int k = (ph[0] > ph[1])?
		((ph[0] > ph[2])? 0 : (ph[0] < ph[2])? 2 : random_bool()? 0 : 2) :
		(ph[0] < ph[1])?
		((ph[1] > ph[2])? 1 : (ph[1] < ph[2])? 2 : random_bool()? 1 : 2) :
		((ph[0] < ph[2])? 2 : (ph[0] > ph[2])? (random_bool()? 0 : 1) : lrand48() % 3);
	a->v = candidate[k] - a->p;
	a->p = candidate[k];
	CGFloat size = AgentWeight * agentWeight;
	if (a->p.x < -size || a->p.x > camXMax+size || a->p.y < -size || a->p.y > 1+size)
		{ reset_agent(a); return; }
	float maxLen = AgentLength * agentLength;
	float segLen = simd_length(a->v);
	TrailCell *newCell = newTrailCell(a->p, segLen);
	newCell->prev = NULL;
	newCell->post = a->head;
	a->head->prev = newCell;
	a->head = newCell;
	a->length += segLen;
	if (a->trailCount >= trailSteps) {
		TrailCell *newTail = a->tail->prev;
		a->length -= newTail->l;
		removeTrailCell(a->tail);
		a->tail = newTail;
	} else a->trailCount ++;
	TrailCell *tc2 = a->tail, *tc1 = tc2->prev;
	while (tc1 != NULL && a->length > maxLen) {
		float seg = tc1->l;
		if (a->length - seg > maxLen) {
			removeTrailCell(tc2);
			a->tail = tc2 = tc1; tc1 = tc1->prev;
			a->length -= seg;
			a->trailCount --;
		} else {
			float dif = a->length - maxLen;
			tc2->p += (tc1->p - tc2->p) * dif / tc1->l;
			tc1->l -= dif;
			a->length = maxLen;
		}
	}
}
static float angleV(simd_float2 v1, simd_float2 v2) {
	float a = atan2(v1.y, v1.x) - atan2(v2.y, v2.x);
	return (a <= -M_PI)? a + M_PI*2 : (a > M_PI)? a - M_PI*2 : a;
}
static void vxEnd(simd_float2 *vx, simd_float2 p1, simd_float2 p2, float size) {
	simd_float2 e = p2 - p1;
	e = (simd_float2){-e.y, e.x} * size / simd_length(e);
	vx[0] = p2 + e;
	vx[1] = p2 - e;
}
static void vxJoint(simd_float2 *vx, simd_float2* p, float size) {
	simd_float2 v1 = p[0] - p[1], v2 = p[2] - p[1];
	simd_float2 e = simd_normalize(v1) + simd_normalize(v2);
	e *= size / sin(angleV(v1, v2) / 2.) / simd_length(e);
	vx[0] = p[1] + e;
	vx[1] = p[1] - e;
}
static NSInteger agent_vector(MyAgent *a, simd_float2 *vx, float *op) {
	if (a->length <= 0. || a->trailCount <= 1) return 0;
	simd_float2 p[a->trailCount];
	TrailCell *tc = a->head;
	for (NSInteger i = 0; i < a->trailCount && tc != NULL; i ++, tc = tc->post) p[i] = tc->p;
	float size = AgentWeight * agentWeight / 2.;
	vxEnd(vx, p[0] + p[0] - p[1], p[0], size);
	for (NSInteger i = 1; i < a->trailCount - 1; i ++)
		vxJoint(vx + i * 2, p + i - 1, size);
	vxEnd(vx + (a->trailCount - 1) * 2, p[a->trailCount - 2], p[a->trailCount - 1], size);
	float z = pow(1./64., agentOpcGrad);
	for (NSInteger i = 0; i < a->trailCount; i ++) {
		float c = get_chemical(AtrctSrcMap, p[i]);
		op[i] = z * c / ((z - 1) * c + 1);
	}
	return a->trailCount * 2;
}
void setup_agents(void) { // called onece in initWidthFrame of PrjctView.
	TrailMemLock = NSLock.new;
	AgentTrailLock = NSLock.new;
	theAgents = malloc(sizeof(MyAgent) * NAgents);
	memset(theAgents, 0, sizeof(MyAgent) * NAgents);
	nThreads = NSProcessInfo.processInfo.processorCount;
#ifdef DEBUG
	NSLog(@"%ld threads.", nThreads);
#endif
	opeQue = NSOperationQueue.new;
}
void change_n_agents(void) {
	theAgents = realloc(theAgents, sizeof(MyAgent) * NAgents);
	memset(theAgents, 0, sizeof(MyAgent) * NAgents);
	reset_agents(); 
}
void reset_agents(void) {
	for (int i = 0; i < NAgents; i ++) reset_agent(&theAgents[i]);
}
static void do_parallel(void (*proc)(MyAgent *)) {
	NSInteger ne = NAgents / nThreads;
	for (NSInteger i = 0; i < nThreads - 1; i ++) {
		NSInteger start = i * ne;
		[opeQue addOperationWithBlock:^{
			for (NSInteger j = 0; j < ne; j ++) proc(&theAgents[start + j]);
		}];
	}
	for (NSInteger i = ne * (nThreads - 1); i < NAgents; i ++) proc(&theAgents[i]);
	[opeQue waitUntilAllOperationsAreFinished];
}
void exocrine_agents(void) {
	do_parallel(exocrine_agent);
}
void move_agents(void) {
	static unsigned long prev_time_us = 0;
	unsigned long now_us = current_time_us();
	elapsedSec = (prev_time_us == 0)? 1./60. : (now_us - prev_time_us) * 1e-6;
	prev_time_us = now_us;
	[AgentTrailLock lock];
	do_parallel(move_agent);
	[AgentTrailLock unlock];
}
static NSInteger agents_vecs(AgentVecInfo info) {
	uint16 ix = 0;
	for (NSInteger i = 0; i < info.nAgents; i ++) {
		uint16 k = agent_vector(info.a + i, info.vx, info.op);
		info.vx += k; info.op += k / 2;
		for (NSInteger j = 0; j < k; j ++, ix ++) info.idx[ix + i] = ix;
		if (i < info.nAgents - 1) info.idx[ix + i] = 0xffff;
	}
	return ix + info.nAgents - 1;	// return the number of indices
}
void agent_vectors(simd_float2 *vx, uint16 *idx, float *op,
	void (^set_metal_com)(NSInteger, NSInteger, NSInteger)) {
	AgentVecInfo info = { theAgents, NAgents / nThreads, vx, idx, op };
	NSInteger np = info.nAgents * trailSteps, ni = np * 2 + info.nAgents - 1,
		nidx[nThreads], *nidxp = nidx;
	[AgentTrailLock lock];
	for (NSInteger i = 0; i < nThreads - 1; i ++, nidxp ++) {
		[opeQue addOperationWithBlock:^{ *nidxp = agents_vecs(info); }];
		info.a += info.nAgents;
		info.vx += np * 2;
		info.idx += ni;
		info.op += np;
	}
	info.nAgents = NAgents - info.nAgents * (nThreads - 1);
	*nidxp = agents_vecs(info);
	[opeQue waitUntilAllOperationsAreFinished];
	[AgentTrailLock unlock];
	for (NSInteger i = 0; i < nThreads; i ++)
		set_metal_com(nidx[i], i * ni, i * np);
}
