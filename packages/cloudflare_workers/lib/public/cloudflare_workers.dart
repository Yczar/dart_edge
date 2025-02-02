import 'dart:js_util' as js_util;

import 'package:js/js.dart';
import 'package:edge/runtime/interop/promise_interop.dart';
import 'package:edge/runtime.dart';
import 'package:edge/runtime/request.dart';
import 'package:edge/runtime/response.dart';

import 'package:js_bindings/js_bindings.dart' as interop;
import '../interop/environment_interop.dart' as interop;
import '../interop/scheduled_event_interop.dart' as interop;
import '../interop/email_message_interop.dart' as interop;
import '../interop/execution_context_interop.dart' as interop;
import '../interop/durable_object_interop.dart' as interop;

import '../public/do/durable_object.dart';
import '../public/execution_context.dart';
import '../public/scheduled_event.dart';
import '../public/email_message.dart';
import '../public/environment.dart';
import 'do/durable_object_state.dart';

@JS('__dartCloudflareFetchHandler')
external set globalDartFetchHandler(
    Promise<interop.Response> Function(interop.Request req,
            interop.Environment env, interop.ExecutionContext ctx)
        f);

@JS('__dartCloudflareScheduledHandler')
external set globalDartScheduledHandler(
    Promise<void> Function(interop.ScheduledEvent event,
            interop.Environment env, interop.ExecutionContext ctx)
        f);

@JS('__dartCloudflareEmailHandler')
external set globalDartEmailHandler(
    Promise<void> Function(interop.EmailMessage message,
            interop.Environment env, interop.ExecutionContext ctx)
        f);

@JS('__dartCloudflareDurableObjects')
external set globalDurableObjects(dynamic value);

typedef CloudflareWorkersFetchEvent = FutureOr<Response> Function(
    Request request, Environment env, ExecutionContext ctx);

typedef CloudflareWorkersScheduledEvent = FutureOr<void> Function(
    ScheduledEvent event, Environment env, ExecutionContext ctx);

typedef CloudflareWorkersEmailEvent = FutureOr<void> Function(
    EmailMessage message, Environment env, ExecutionContext ctx);

typedef CloudflareWorkersDurableObjects = Map<String, DurableObject Function()>;

void attachFetchHandler(CloudflareWorkersFetchEvent handler) {
  globalDartFetchHandler = allowInterop((interop.Request req,
      interop.Environment env, interop.ExecutionContext ctx) {
    return futureToPromise(Future(() async {
      final response = await handler(
        requestFromJsObject(req),
        environmentFromJsObject(env),
        executionContextFromJsObject(ctx),
      );
      return response.delegate;
    }));
  });
}

void attachScheduledHandler(CloudflareWorkersScheduledEvent handler) {
  globalDartScheduledHandler = allowInterop((interop.ScheduledEvent event,
      interop.Environment env, interop.ExecutionContext ctx) {
    return futureToPromise(Future(() async {
      return handler(
        scheduledEventFromJsObject(event),
        environmentFromJsObject(env),
        executionContextFromJsObject(ctx),
      );
    }));
  });
}

void attachEmailHandler(CloudflareWorkersEmailEvent handler) {
  globalDartEmailHandler = allowInterop((interop.EmailMessage message,
      interop.Environment env, interop.ExecutionContext ctx) {
    return futureToPromise(Future(() async {
      return handler(
        emailMessageFromJsObject(message),
        environmentFromJsObject(env),
        executionContextFromJsObject(ctx),
      );
    }));
  });
}

void attachDurableObjects(CloudflareWorkersDurableObjects instances) {
  globalDurableObjects = js_util.jsify({
    for (final instance in instances.entries)
      instance.key: allowInterop(
          (interop.DurableObjectState state, interop.Environment env) {
        final cls = instance.value();

        // Attach the state and environment to the delegate.
        final delegate = cls.delegate;
        delegate.state = state;
        delegate.env = env;

        // Call the instance fetch handler, and return the delegate request.
        delegate.fetch = allowInterop((interop.Request requestObj) {
          return futureToPromise(Future(() async {
            final response = await cls.fetch(requestFromJsObject(requestObj));
            return response.delegate;
          }));
        });

        // Call the instance alarm handler.
        delegate.alarm = allowInterop(() {
          return futureToPromise(Future(() async {
            await cls.alarm();
          }));
        });

        return delegate;
      })
  });
}

class CloudflareWorkers {
  final CloudflareWorkersDurableObjects? durableObjects;

  final CloudflareWorkersFetchEvent? fetch;

  final CloudflareWorkersScheduledEvent? scheduled;

  final CloudflareWorkersEmailEvent? email;

  CloudflareWorkers({
    this.fetch,
    this.scheduled,
    this.email,
    this.durableObjects,
  }) {
    // Setup the runtime environment.
    setupRuntime();

    // Attach the fetch handler to the global object.
    if (fetch != null) {
      attachFetchHandler(fetch!);
    }

    // Attach the scheduled handler to the global object.
    if (scheduled != null) {
      attachScheduledHandler(scheduled!);
    }

    // Attach the email handler to the global object.
    if (email != null) {
      attachEmailHandler(email!);
    }

    // Attach the durable objects to the global object, by name.
    if (durableObjects != null) {
      attachDurableObjects(durableObjects!);
    }
  }
}
